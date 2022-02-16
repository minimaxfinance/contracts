// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./helpers/SafeBEP20.sol";
import "./MinimaxStaking.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IPancakeRouter.sol";
import "./interfaces/ISmartChefInitializable.sol";
import "./ProxyCaller.sol";

/*
    MinimaxMain
*/
contract MinimaxMain is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    address public cakeAddress; // "0x0e09fabb73bd3ade0a17ecc321fd13a19e81ce82"
    address public cakeOracleAddress; // "0xb6064ed41d4f67e353768aa239ca86f4f73665a1"
    address public busdAddress; // "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56"
    address public cakeRouterAddress; // "0x10ED43C718714eb63d5aA57B78B54704E256024E"
    address public minimaxStaking;

    event PositionWasCreated(uint indexed positionIndex);
    event PositionWasModified(uint indexed positionIndex);
    event PositionWasClosed(uint indexed positionIndex);

    uint public constant FEE_MULTIPLIER = 1e8;
    uint public constant SLIPPAGE_MULTIPLIER = 1e8;
    // From chainlink price oracle (decimals)
    uint public constant PRICE_MULTIPLIER = 1e8;

    struct PositionInfo {
        uint stakedAmount;
        uint feeAmount;
        uint stopLossPrice;
        uint maxSlippage;
        address poolAddress;
        address owner;
        address rewardToken;
        address callerAddress;
        bool closed;
        uint takeProfitPrice;
    }

    uint lastPositionIndex;

    // Not an array for upgradability of PositionInfo struct
    mapping(uint => PositionInfo) public positions;
    mapping(address => bool) public isLiquidator;

    bytes4 private constant ENTER_STAKING_SELECTOR = bytes4(keccak256("enterStaking(uint256)"));
    bytes4 private constant LEAVE_STAKING_SELECTOR = bytes4(keccak256("leaveStaking(uint256)"));
    bytes4 private constant DEPOSIT_SELECTOR = bytes4(keccak256("deposit(uint256)"));
    bytes4 private constant WITHDRAW_SELECTOR = bytes4(keccak256("withdraw(uint256)"));
    bytes4 private constant APPROVE_SELECTOR = bytes4(keccak256("approve(address,uint256)"));

    address[] private availableCallers;

    // Fee threshold
    struct FeeThreshold {
        uint fee;
        uint stakedAmountThreshold;
    }

    FeeThreshold[] public depositFees;

    address masterChefAddress; // "0x73feaa1eE314F8c655E354234017bE2193C9E24E"

    mapping(address => bool) public smartChefPools;

    bytes4 private constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));

    // Storage section ends!

    modifier onlyLiquidator() {
        require(isLiquidator[address(msg.sender)], "only one of liquidators can close positions");
        _;
    }

    using SafeBEP20 for IBEP20;
    using SafeMath for uint;

    function initialize(
        address _minimaxStaking,
        address _cakeAddress,
        address _cakeOracleAddress,
        address _busdAddress,
        address _cakeRouterAddress,
        address _masterChefAddress
    ) external initializer {
        minimaxStaking = _minimaxStaking;
        cakeAddress = _cakeAddress;
        cakeOracleAddress = _cakeOracleAddress;
        busdAddress = _busdAddress;
        cakeRouterAddress = _cakeRouterAddress;
        masterChefAddress = _masterChefAddress;

        __Ownable_init();
        __ReentrancyGuard_init();

        // staking pool
        depositFees.push(
            FeeThreshold({
                fee: 100000, // 0.1%
                stakedAmountThreshold: 1000 * 1e18 // all stakers <= 1000 MMX would have 0.1% fee for deposit
            })
        );

        depositFees.push(
            FeeThreshold({
                fee: 90000, // 0.09%
                stakedAmountThreshold: 5000 * 1e18
            })
        );

        depositFees.push(
            FeeThreshold({
                fee: 80000, // 0.08%
                stakedAmountThreshold: 10000 * 1e18
            })
        );

        depositFees.push(
            FeeThreshold({
                fee: 70000, // 0.07%
                stakedAmountThreshold: 50000 * 1e18
            })
        );
        depositFees.push(
            FeeThreshold({
                fee: 50000, // 0.05%
                stakedAmountThreshold: 10000000 * 1e18 // this level doesn't matter
            })
        );
    }

    // May run out of gas!
    function setSmartChefPools(address[] calldata pools, bool[] calldata allowances) external onlyOwner {
        for (uint i = 0; i < pools.length; i++) {
            smartChefPools[pools[i]] = allowances[i];
        }
    }

    function getSlippageMultiplier() public pure returns (uint) {
        return SLIPPAGE_MULTIPLIER;
    }

    function getPriceMultiplier() public pure returns (uint) {
        return PRICE_MULTIPLIER;
    }

    function getUserFee() public view returns (uint) {
        MinimaxStaking staking = MinimaxStaking(minimaxStaking);

        uint amountPool2 = staking.getUserAmount(2, msg.sender);
        uint amountPool3 = staking.getUserAmount(3, msg.sender);
        uint totalStakedAmount = amountPool2.add(amountPool3);

        uint length = depositFees.length;

        for (uint bucketId = 0; bucketId < length; ++bucketId) {
            uint threshold = depositFees[bucketId].stakedAmountThreshold;
            if (totalStakedAmount <= threshold) {
                return depositFees[bucketId].fee;
            }
        }
        return depositFees[length - 1].fee;
    }

    function getPositionInfo(uint positionIndex) external view returns (PositionInfo memory) {
        return positions[positionIndex];
    }

    // May run out of gas if 'amount' is big
    function addNewCallers(uint amount) external onlyOwner {
        for (uint i = 0; i < amount; i++) {
            ProxyCaller caller = new ProxyCaller();
            availableCallers.push(address(caller));
        }
    }

    function emergencyWithdrawCake(address to, uint cakeAmount) external onlyOwner {
        IBEP20(cakeAddress).safeTransfer(to, cakeAmount);
    }

    function setDepositFee(uint poolIdx, uint feeShare) external onlyOwner {
        require(poolIdx < depositFees.length, "wrong pool index");
        depositFees[poolIdx].fee = feeShare;
    }

    function setCakeOracleAddress(address oracleAddress) external onlyOwner {
        cakeOracleAddress = oracleAddress;
    }

    function setCakeRouterAddress(address routerAddress) external onlyOwner {
        cakeRouterAddress = routerAddress;
    }

    function setMinimaxStakingAddress(address stakingAddress) external onlyOwner {
        minimaxStaking = stakingAddress;
    }

    function setMasterChefAddress(address masterChefAddressVal) external onlyOwner {
        masterChefAddress = masterChefAddressVal;
    }

    function stakeCake(
        address poolAddress,
        uint256 cakeAmount,
        uint256 maxSlippage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external nonReentrant returns (uint) {
        emit PositionWasCreated(lastPositionIndex);

        require(stopLossPrice != 0, "stakeCake: stop-loss price is zero");
        require(takeProfitPrice != 0, "stakeCake: take-profit price is zero");

        bytes4 stakingSelector = DEPOSIT_SELECTOR;
        address rewardToken = cakeAddress;
        if (poolAddress == masterChefAddress) {
            stakingSelector = ENTER_STAKING_SELECTOR;
        } else {
            require(smartChefPools[poolAddress], "stakeCake: got not allowed pool");
            rewardToken = address(SmartChefInitializable(poolAddress).rewardToken());
        }

        address caller = getAvailableCaller();

        IBEP20(cakeAddress).safeTransferFrom(address(msg.sender), address(this), cakeAmount);

        uint userFeeShare = getUserFee();
        uint userFeeAmount = cakeAmount.mul(userFeeShare).div(FEE_MULTIPLIER);
        uint amountToStake = cakeAmount.sub(userFeeAmount);

        lastPositionIndex += 1;

        positions[lastPositionIndex - 1] = PositionInfo({
            stakedAmount: amountToStake,
            feeAmount: userFeeAmount,
            stopLossPrice: stopLossPrice,
            maxSlippage: maxSlippage,
            poolAddress: poolAddress,
            owner: address(msg.sender),
            rewardToken: rewardToken,
            callerAddress: caller,
            closed: false,
            takeProfitPrice: takeProfitPrice
        });

        stakeViaCaller(positions[lastPositionIndex - 1], amountToStake, stakingSelector);
        // No rewards to dump
        return lastPositionIndex - 1;
    }

    function deposit(uint positionIndex, uint amount) external nonReentrant {
        bytes4 stakingSelector = DEPOSIT_SELECTOR;
        if (positions[positionIndex].poolAddress == masterChefAddress) {
            stakingSelector = ENTER_STAKING_SELECTOR;
        }
        depositImpl(positionIndex, amount, stakingSelector);
    }

    function setLiquidator(address user, bool value) external onlyOwner {
        isLiquidator[user] = value;
    }

    function changeStopLossPrice(uint positionIndex, uint newStopLossPrice) external nonReentrant {
        emit PositionWasModified(positionIndex);
        PositionInfo storage position = positions[positionIndex];
        require(position.owner == address(msg.sender), "stop loss may be changed only by position owner");
        require(newStopLossPrice != 0, "changeStopLossPrice: new price is zero");
        position.stopLossPrice = newStopLossPrice;
    }

    function withdrawAll(uint positionIndex) external nonReentrant {
        PositionInfo storage position = positions[positionIndex];
        bytes4 withdrawSelector = WITHDRAW_SELECTOR;
        if (position.poolAddress == masterChefAddress) {
            withdrawSelector = LEAVE_STAKING_SELECTOR;
        }
        withdrawImpl(position, positionIndex, position.stakedAmount, withdrawSelector);
    }

    function alterPositionParams(
        uint positionIndex,
        uint newAmount,
        uint newStopLossPrice,
        uint newTakeProfitPrice,
        uint newSlippage
    ) external nonReentrant {
        PositionInfo storage position = positions[positionIndex];
        require(position.owner == address(msg.sender), "stop loss may be changed only by position owner");
        require(newStopLossPrice != 0, "changeStopLossPrice: new price is zero");
        require(newSlippage != 0, "slippage: new slippage is zero");

        bytes4 depositSelector = DEPOSIT_SELECTOR;
        bytes4 withdrawSelector = WITHDRAW_SELECTOR;
        if (position.poolAddress == masterChefAddress) {
            depositSelector = ENTER_STAKING_SELECTOR;
            withdrawSelector = LEAVE_STAKING_SELECTOR;
        }

        position.stopLossPrice = newStopLossPrice;
        position.takeProfitPrice = newTakeProfitPrice;
        position.maxSlippage = newSlippage;

        if (newAmount < position.stakedAmount) {
            uint withdrawAmount = position.stakedAmount.sub(newAmount);
            withdrawImpl(position, positionIndex, withdrawAmount, withdrawSelector);
        } else if (newAmount > position.stakedAmount) {
            uint depositAmount = newAmount.sub(position.stakedAmount);
            depositImpl(positionIndex, depositAmount, depositSelector);
        } else {
            emit PositionWasModified(positionIndex);
        }
    }

    function withdraw(uint positionIndex, uint amount) external nonReentrant {
        PositionInfo storage position = positions[positionIndex];
        bytes4 withdrawSelector = WITHDRAW_SELECTOR;
        if (position.poolAddress == masterChefAddress) {
            withdrawSelector = LEAVE_STAKING_SELECTOR;
        }
        withdrawImpl(position, positionIndex, amount, withdrawSelector);
    }

    function dumpRewards(PositionInfo storage position) private {
        uint rewardAmount = IBEP20(position.rewardToken).balanceOf(position.callerAddress);
        if (rewardAmount != 0) {
            transferTokensViaCaller(position, position.rewardToken, position.owner, rewardAmount);
        }
    }

    // Emits `PositionWasClosed` always.
    function liquidateByIndexImpl(uint positionIndex) private {
        emit PositionWasClosed(positionIndex);

        bytes4 withdrawSelector = WITHDRAW_SELECTOR;
        if (positions[positionIndex].poolAddress == masterChefAddress) {
            withdrawSelector = LEAVE_STAKING_SELECTOR;
        }

        PositionInfo storage position = positions[positionIndex];
        verifyPositionReadinessForLiquidation(positionIndex);
        withdrawViaCaller(position, position.stakedAmount, withdrawSelector);

        transferTokensViaCaller(position, cakeAddress, address(this), position.stakedAmount);
        // Firstly, 'transferTokensViaCaller', then 'dumpRewards': order is important here when (rewardToken == CAKE)
        dumpRewards(position);

        IPriceOracle cakePriceOracle = IPriceOracle(cakeOracleAddress);
        uint latestPrice = uint(cakePriceOracle.latestAnswer());
        finishLiquidationAfterUnstaking(positionIndex, latestPrice);
    }

    function liquidateByIndex(uint positionIndex) external nonReentrant onlyLiquidator {
        liquidateByIndexImpl(positionIndex);
    }

    // May run out of gas if array length is too big!
    function liquidateManyByIndex(uint[] calldata positionIndexes) external nonReentrant onlyLiquidator {
        for (uint i = 0; i < positionIndexes.length; ++i) {
            liquidateByIndexImpl(positionIndexes[i]);
        }
    }

    function returnCaller(address caller) private {
        availableCallers.push(caller);
    }

    function approveViaCaller(
        address caller,
        address callee,
        address user,
        uint allowance
    ) private {
        (bool success, bytes memory data) = ProxyCaller(caller).exec(
            callee,
            abi.encodeWithSelector(APPROVE_SELECTOR, user, allowance)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "approve via caller");
    }

    function getAvailableCaller() private returns (address) {
        if (availableCallers.length == 0) {
            ProxyCaller caller = new ProxyCaller();
            return address(caller);
        }
        address res = availableCallers[availableCallers.length - 1];
        availableCallers.pop();
        return res;
    }

    function stakeViaCaller(
        PositionInfo storage position,
        uint amount,
        bytes4 poolSelector
    ) private {
        IBEP20(cakeAddress).safeTransfer(position.callerAddress, amount);
        approveViaCaller(position.callerAddress, cakeAddress, position.poolAddress, amount);
        (bool success, bytes memory data) = ProxyCaller(position.callerAddress).exec(
            position.poolAddress,
            abi.encodeWithSelector(poolSelector, amount)
        );
        require(success && (data.length == 0), "stake via caller");
    }

    // Emits `PositionsWasModified` always.
    function depositImpl(
        uint positionIndex,
        uint amount,
        bytes4 depositSelector
    ) private {
        emit PositionWasModified(positionIndex);

        PositionInfo storage position = positions[positionIndex];
        require(position.owner == address(msg.sender), "deposit: only position owner allowed");
        require(position.closed == false, "deposit: position is closed");

        IBEP20(cakeAddress).safeTransferFrom(address(msg.sender), address(this), amount);

        uint userFeeShare = getUserFee();
        uint userFeeAmount = amount.mul(userFeeShare).div(FEE_MULTIPLIER);
        uint amountToDeposit = amount.sub(userFeeAmount);

        position.stakedAmount = (position.stakedAmount).add(amountToDeposit);
        position.feeAmount = (position.feeAmount).add(userFeeAmount);

        stakeViaCaller(position, amountToDeposit, depositSelector);
        dumpRewards(position);
    }

    function transferTokensViaCaller(
        PositionInfo storage position,
        address token,
        address to,
        uint amount
    ) private {
        (bool success, ) = ProxyCaller(position.callerAddress).exec(
            token,
            abi.encodeWithSelector(TRANSFER_SELECTOR, to, amount)
        );
        require(success, "transferTokensViaCaller: send token to owner");
    }

    function withdrawViaCaller(
        PositionInfo storage position,
        uint amount,
        bytes4 withdrawSelector
    ) private {
        (bool success, bytes memory data) = ProxyCaller(position.callerAddress).exec(
            position.poolAddress,
            abi.encodeWithSelector(withdrawSelector, amount)
        );
        require(success && (data.length == 0), "withdrawViaCaller: unstaking");
    }

    // Emits:
    //   * `PositionWasClosed`,   if `amount == position.stakedAmount`.
    //   * `PositionWasModified`, otherwise.
    function withdrawImpl(
        PositionInfo storage position,
        uint positionIndex,
        uint amount,
        bytes4 withdrawSelector
    ) private {
        require(position.owner == address(msg.sender), "withdraw: only position owner allowed");
        require(position.closed == false, "withdraw: position is closed");
        require(amount <= position.stakedAmount, "withdraw: withdraw amount exceeds staked amount");
        withdrawViaCaller(position, amount, withdrawSelector);
        transferTokensViaCaller(position, cakeAddress, position.owner, amount);
        dumpRewards(position);

        if (amount == position.stakedAmount) {
            emit PositionWasClosed(positionIndex);
            position.closed = true;
            returnCaller(position.callerAddress);
        } else {
            emit PositionWasModified(positionIndex);
            position.stakedAmount = (position.stakedAmount).sub(amount);
        }
    }

    function verifyPositionReadinessForLiquidation(uint positionIndex) private view returns (uint) {
        PositionInfo storage position = positions[positionIndex];
        require(position.closed == false, "isPositionReadyForLiquidation: position is closed");
        require(position.owner != address(0), "position is not created");

        IPriceOracle cakePriceOracle = IPriceOracle(cakeOracleAddress);
        uint latestPrice = uint(cakePriceOracle.latestAnswer());
        require(
            (latestPrice < position.stopLossPrice) || (latestPrice > position.takeProfitPrice),
            "isPositionReadyForLiquidation: incorrect price level"
        );

        return latestPrice;
    }

    function finishLiquidationAfterUnstaking(uint positionIndex, uint latestPrice) private {
        PositionInfo storage position = positions[positionIndex];

        IPancakeRouter dexRouter = IPancakeRouter(cakeRouterAddress);

        // Optimistic conversion BUSD amount
        uint minAmountOut = position.stakedAmount.mul(latestPrice).div(PRICE_MULTIPLIER);
        // Accounting slippage
        minAmountOut = minAmountOut.sub(minAmountOut.mul(position.maxSlippage).div(SLIPPAGE_MULTIPLIER));

        address[] memory path = new address[](2);
        path[0] = cakeAddress;
        path[1] = busdAddress;

        IBEP20(cakeAddress).safeIncreaseAllowance(address(cakeRouterAddress), position.stakedAmount);

        dexRouter.swapExactTokensForTokens(
            position.stakedAmount,
            minAmountOut,
            path, /* path */
            position.owner, /* to */
            block.timestamp /* deadline */
        );

        // Transfer fee to liquidator address
        IBEP20(cakeAddress).safeTransfer(msg.sender, position.feeAmount);

        position.closed = true;
        returnCaller(position.callerAddress);
    }
}
