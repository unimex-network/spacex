// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./SpaceXToken.sol";
import "./interfaces/IReferral.sol";
import "./interfaces/IUnimexPool.sol";
import "./interfaces/IUnimexFactory.sol";

// MasterChef is the master of SpaceXToken. He can make SpaceX and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once SpaceX is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract SpaceXChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        uint256 wethRewardDebt;
        //
        // We do some fancy math here. Basically, any point in time, the amount of SpaceX
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accSpaceXPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accSpaceXPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. SpaceX to distribute per block.
        uint256 lastRewardBlock;  // Last block number that SpaceX distribution occurs.
        uint256 accSpaceXPerShare;   // Accumulated SpaceX per share, times 1e18. See below.
        uint256 accWethPerShare;   // Accumulated SpaceX per share, times 1e18. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points
        uint16 withdrawalFeeBP;   // Withdrawal fee in basis points
	    bool unimexIntegration;   //Unimex integration
    }

    // The SpaceX TOKEN!
    SpaceXToken public immutable spaceXToken;
    IUniMexFactory public unimexFactory;
    address public devAddress;
    address public feeAddress;

    ERC20 public immutable WETH;

    // SpaceX tokens created per block.
    uint256 public spaceXPerBlock = 1 ether;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when SpaceX mining starts.
    uint256 public startBlock;

    // SpaceX referral contract address.
    IReferral public immutable referral;
    // Referral commission rate in basis points.
    uint16 public referralCommissionRate = 200;
    // Max referral commission rate: 5%.
    uint16 public constant MAXIMUM_REFERRAL_COMMISSION_RATE = 500;

    uint256 constant MAX_SPACEX_SUPPLY = 10_000_000 ether;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event SetReferralAddress(address indexed user, IReferral indexed newAddress);
    event UpdateEmissionRate(address indexed user, uint256 spaceXPerBlock);
    event ReferralCommissionPaid(address indexed user, address indexed referrer, uint256 commissionAmount);
    event OnStartBlockUpdate(uint256 newBlock);
    event OnReferralCommissionRateUpdate(uint16 referralCommissionRate);
    event Add(uint256 allocPoint, address lpToken, uint16 depositFeeBP, uint16 withdrawalFeeBP, bool unimexIntegration);
    event Set(uint256 pid, uint256 allocPoint, uint16 depositFeeBP, uint16 withdrawalFeeBP, bool unimexIntegration);
    event WethDistributed(uint256 amount);

    constructor(
        SpaceXToken _spaceX,
        uint256 _startBlock,
	    address _unimexFactory,
        address _devAddress,
        address _feeAddress,
        address _referralAddress
    ) public {
        require(address(_spaceX) != address(0) &&
                _unimexFactory != address(0) && 
                _devAddress != address(0) &&
                _feeAddress != address(0) &&
                _referralAddress != address(0), "zero addresses");
        spaceXToken = _spaceX;
        startBlock = _startBlock;

	    unimexFactory = IUniMexFactory(_unimexFactory);
        WETH = ERC20(unimexFactory.WETH());
        devAddress = _devAddress;
        feeAddress = _feeAddress;
        referral = IReferral(_referralAddress);
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    mapping(IERC20 => bool) public poolExistence;
    modifier nonDuplicated(IERC20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IERC20 _lpToken, uint16 _depositFeeBP, uint16 _withdrawalFeeBP, bool _unimexIntegration) external onlyOwner nonDuplicated(_lpToken) {
        require(_depositFeeBP <= 1000, "add: invalid deposit fee basis points");
        require(_withdrawalFeeBP <= 1000, "add: invalid deposit fee basis points");
        _lpToken.balanceOf(address(this)); //safety check that address is a token address
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;
        poolInfo.push(PoolInfo({
			lpToken: _lpToken,
			allocPoint: _allocPoint,
			lastRewardBlock: lastRewardBlock,
			accSpaceXPerShare: 0,
			accWethPerShare: 0,
			depositFeeBP: _depositFeeBP,
            withdrawalFeeBP: _withdrawalFeeBP,
			unimexIntegration: _unimexIntegration
        }));
		if(_unimexIntegration) {
			address unimexPool = unimexFactory.getPool(address(_lpToken));
			require(unimexPool != address(0), "add: no unimex pool");
            _lpToken.approve(unimexPool, type(uint256).max);
		}
        emit Add(_allocPoint, address(_lpToken), _depositFeeBP, _withdrawalFeeBP, _unimexIntegration);
    }

    // Update the given pool's SpaceX allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, uint16 _withdrawalFeeBP, bool _unimexIntegration) external onlyOwner {
        require(_depositFeeBP <= 1000, "set: invalid deposit fee basis points");
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
        poolInfo[_pid].withdrawalFeeBP = _withdrawalFeeBP;
		poolInfo[_pid].unimexIntegration = _unimexIntegration;
        IERC20 lpToken = poolInfo[_pid].lpToken;
		IUniMexPool unimexPool = IUniMexPool(unimexFactory.getPool(address(lpToken)));
		if(_unimexIntegration) {
			//deposit lp balance to the pool
			require(address(unimexPool) != address(0), "set: no unimex pool");
            lpToken.approve(address(unimexPool), type(uint256).max);
            unimexPool.deposit(lpToken.balanceOf(address(this)));
		} else {
            if(address(unimexPool) != address(0)) {
                uint256 depositedBalance = unimexPool.correctedBalanceOf(address(this));
                if(depositedBalance > 0) {
                    unimexPool.withdraw(depositedBalance);
                }
                lpToken.approve(address(unimexPool), 0);
            }
        }
        emit Set(_pid, _allocPoint, _depositFeeBP, _withdrawalFeeBP, _unimexIntegration);
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

    // View function to see pending SpaceX on frontend.
    function pendingSpaceX(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accSpaceXPerShare = pool.accSpaceXPerShare;
        uint256 lpSupply = depositedBalance(_pid);
        if (block.number > pool.lastRewardBlock && lpSupply != 0 && totalAllocPoint > 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 spaceXReward = multiplier.mul(spaceXPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accSpaceXPerShare = accSpaceXPerShare.add(spaceXReward.mul(1e18).div(lpSupply));
        }
        return user.amount.mul(accSpaceXPerShare).div(1e18).sub(user.rewardDebt);
    }

    function pendingWeth(uint256 _pid, address _user) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        return user.amount.mul(pool.accWethPerShare).div(1e18).sub(user.wethRewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = depositedBalance(_pid);
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 spaceXReward = multiplier.mul(spaceXPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        mintCapped(devAddress, spaceXReward.div(10));
        mintCapped(address(this), spaceXReward);
        pool.accSpaceXPerShare = pool.accSpaceXPerShare.add(spaceXReward.mul(1e18).div(lpSupply));

        pool.lastRewardBlock = block.number;

        if(pool.unimexIntegration) {
            uint256 wethRewards = claimUnimexRewards(address(pool.lpToken));
            pool.accWethPerShare = pool.accWethPerShare.add(wethRewards.mul(1e18).div(lpSupply));
        }
    }


    /**
    * @notice distribute additional WETH reward for pools
    * @param _amount amount of WETH to distribute
    * @param _pid id of the pool to distribute
     */
    function distributeWeth(uint256 _amount, uint256 _pid) external {
        WETH.transferFrom(msg.sender, address(this), _amount);
        PoolInfo storage pool = poolInfo[_pid];
        uint256 lpSupply = depositedBalance(_pid);
        pool.accWethPerShare = pool.accWethPerShare.add(_amount.mul(1e18).div(lpSupply));
        emit WethDistributed(_amount);
    }

    function depositedBalance(uint256 _pid) private view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        uint256 result = pool.lpToken.balanceOf(address(this));
        if(pool.unimexIntegration) {
            IUniMexPool unimexPool = IUniMexPool(unimexFactory.getPool(address(pool.lpToken)));
            result = result.add(unimexPool.balanceOf(address(this)));
        } 
        return result;
    }

    // Deposit LP tokens to MasterChef for SpaceX allocation.
    function deposit(uint256 _pid, uint256 _amount, address _referrer) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (_amount > 0 && address(referral) != address(0) && _referrer != address(0) && _referrer != msg.sender) {
            referral.recordReferral(msg.sender, _referrer);
        }
        if (user.amount > 0) {
            //pay SpaceX
            uint256 pending = user.amount.mul(pool.accSpaceXPerShare).div(1e18).sub(user.rewardDebt);
            if (pending > 0) {
                safeSpaceXTransfer(msg.sender, pending);
                payReferralCommission(msg.sender, pending);
            }
            //pay WETH
            uint256 wethDivs = pendingWeth(_pid, msg.sender);
            if(wethDivs > 0) {
                safeWethTransfer(msg.sender, wethDivs);
            }
        }
        if (_amount > 0) {
            uint256 balanceBefore = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            _amount = pool.lpToken.balanceOf(address(this)).sub(balanceBefore); //update _amount if any transfer fees were applied
            if (pool.depositFeeBP > 0) {
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee);
            } else {
                user.amount = user.amount.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accSpaceXPerShare).div(1e18);
        user.wethRewardDebt = user.amount.mul(pool.accWethPerShare).div(1e18);

        if(pool.unimexIntegration) {
            //deposit to the unimex pool
            IERC20 lpToken = poolInfo[_pid].lpToken;
            address unimexPool = unimexFactory.getPool(address(lpToken));
            require(unimexPool != address(0), "set: no unimex pool");
            IUniMexPool(unimexPool).deposit(lpToken.balanceOf(address(this)));
        }
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accSpaceXPerShare).div(1e18).sub(user.rewardDebt);
        if (pending > 0) {
            safeSpaceXTransfer(msg.sender, pending);
            payReferralCommission(msg.sender, pending);
        }
        //pay WETH
        uint256 wethDivs = pendingWeth(_pid, msg.sender);
        if(wethDivs > 0) {
            safeWethTransfer(msg.sender, wethDivs);
        }

        if (_amount > 0) {
            if(pool.unimexIntegration) {
                //withdraw from the unimex pool
                address unimexPool = unimexFactory.getPool(address(pool.lpToken));
                IUniMexPool(unimexPool).withdraw(_amount);
            }
            user.amount = user.amount.sub(_amount);
            if (pool.withdrawalFeeBP > 0) {
                uint256 withdrawFee = _amount.mul(pool.withdrawalFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, withdrawFee);
                pool.lpToken.safeTransfer(address(msg.sender), _amount.sub(withdrawFee));
            } else {
                pool.lpToken.safeTransfer(address(msg.sender), _amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accSpaceXPerShare).div(1e18);
        user.wethRewardDebt = user.amount.mul(pool.accWethPerShare).div(1e18);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        if(pool.unimexIntegration) {
            //withdraw from the unimex pool
            address unimexPool = unimexFactory.getPool(address(pool.lpToken));
            IUniMexPool(unimexPool).withdraw(amount);
        }
        user.amount = 0;
        user.rewardDebt = 0;
        user.wethRewardDebt = 0;
        if(pool.withdrawalFeeBP > 0) {
            uint256 withdrawFee = amount.mul(pool.withdrawalFeeBP).div(10000);
            pool.lpToken.safeTransfer(feeAddress, withdrawFee);
            pool.lpToken.safeTransfer(address(msg.sender), amount.sub(withdrawFee));
        } else {
            pool.lpToken.safeTransfer(address(msg.sender), amount);
        }
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe spaceX transfer function, just in case if rounding error causes pool to not have enough SpaceX.
    function safeSpaceXTransfer(address _to, uint256 _amount) internal {
        uint256 spaceXBal = spaceXToken.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > spaceXBal) {
            transferSuccess = spaceXToken.transfer(_to, spaceXBal);
        } else {
            transferSuccess = spaceXToken.transfer(_to, _amount);
        }
        require(transferSuccess, "safeSpaceXTransfer: Transfer failed");
    }

    function safeWethTransfer(address _to, uint256 _amount) internal {
        uint256 wethBal = WETH.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > wethBal) {
            transferSuccess = WETH.transfer(_to, wethBal);
        } else {
            transferSuccess = WETH.transfer(_to, _amount);
        }
        require(transferSuccess, "safeWethTransfer: Transfer failed");
    }

    // Update dev address by the previous dev.
    function setDevAddress(address _devAddress) external onlyOwner {
        require(devAddress != address(0), "zero address");
        devAddress = _devAddress;
        emit SetDevAddress(msg.sender, _devAddress);
    }

    function setFeeAddress(address _feeAddress) external onlyOwner {
        require(_feeAddress != address(0), "zero address");
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    function updateEmissionRate(uint256 _spaceXPerBlock) external onlyOwner {
        require(_spaceXPerBlock <= 100 ether, "updateEmissionRate: exceeds max");
        massUpdatePools();
        spaceXPerBlock = _spaceXPerBlock;
        emit UpdateEmissionRate(msg.sender, _spaceXPerBlock);
    }

    // Update referral commission rate by the owner
    function setReferralCommissionRate(uint16 _referralCommissionRate) external onlyOwner {
        require(_referralCommissionRate <= MAXIMUM_REFERRAL_COMMISSION_RATE, "setReferralCommissionRate: invalid referral commission rate basis points");
        referralCommissionRate = _referralCommissionRate;
        emit OnReferralCommissionRateUpdate(referralCommissionRate);
    }

    // Pay referral commission to the referrer who referred this user.
    function payReferralCommission(address _user, uint256 _pending) internal {
        if (address(referral) != address(0) && referralCommissionRate > 0) {
            address referrer = referral.getReferrer(_user);
            uint256 commissionAmount = _pending.mul(referralCommissionRate).div(10000);

            if (referrer != address(0) && commissionAmount > 0) {
                spaceXToken.mint(referrer, commissionAmount);
                emit ReferralCommissionPaid(_user, referrer, commissionAmount);
            }
        }
    }

    // Only update before start of farm
    function updateStartBlock(uint256 _startBlock) external onlyOwner {
        require(startBlock > block.number, "Farm already started");
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            PoolInfo storage pool = poolInfo[pid];
            pool.lastRewardBlock = _startBlock;
        }
        startBlock = _startBlock;
        emit OnStartBlockUpdate(startBlock);
    }

    function claimUnimexRewards(address lpToken) private returns (uint256) {
        IUniMexPool unimexPool = IUniMexPool(unimexFactory.getPool(lpToken));
        if(unimexPool.dividendsOf(address(this)) > 0) {
            uint256 wethBalanceBefore = WETH.balanceOf(address(this));
            unimexPool.claim();
            return WETH.balanceOf(address(this)).sub(wethBalanceBefore);
        } else {
            return 0;
        }
    }

    function mintCapped(address to, uint256 amount) private {
        uint256 totalSupply = spaceXToken.totalSupply();
        if(totalSupply.add(amount) > MAX_SPACEX_SUPPLY) {
            spaceXToken.mint(to, MAX_SPACEX_SUPPLY.sub(totalSupply));
        } else {
            spaceXToken.mint(to, amount);
        }
    }

}
