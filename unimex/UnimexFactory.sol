// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";

import './UnimexPool.sol';
import './Uniswap.sol';

contract UniMexFactory is Ownable {
    using SafeMath for uint256;

    address public margin;
    address[] public allPools;
    
    address public WETH;
    IUniswapV2Factory public UNISWAP_FACTORY;
    uint256 constant private FLOAT_SCALAR = 2**64;

    struct Pool {
        address ethAddr;
        uint256 maxLeverage;
        uint256 utilizationScaled;
    }
    
    mapping(address => Pool) public poolInfo;
    mapping(address => bool) public allowed;
    mapping(address => bool) public allowedMargins;

    event OnPoolCreated(address indexed pair, address pool, uint256 poolLength);

    constructor(address _WETH, address _UNISWAP) public {
        WETH = _WETH;
        UNISWAP_FACTORY = IUniswapV2Factory(_UNISWAP);
        allowed[WETH] = true;
    }

    function setMarginAllowed(address _margin, bool _allowed) external onlyOwner {
        require(_margin != address(0));
        allowedMargins[_margin] = _allowed;
    }
    
    function setUtilizationScaled(address _token, uint256 _utilizationScaled) external onlyOwner returns(uint256) {
        require(allowed[_token] = true);
        require(_utilizationScaled < FLOAT_SCALAR);
        poolInfo[_token].utilizationScaled = _utilizationScaled;
    }
    
    function setMaxLeverage(address _token, uint256 _leverage) external onlyOwner returns(uint256) {
        require(allowed[_token] = true);
        require(_leverage >= 1 && _leverage <= 5);
        poolInfo[_token].maxLeverage = _leverage;
    }

    function addPool(address _token) external {
        address token0;
        address token1;
        (token0, token1) = UniswapV2Library.sortTokens(_token, WETH);
        require(UNISWAP_FACTORY.getPair(token0, token1) != address(0) , 'INVALID_UNISWAP_PAIR');
        allowed[_token] = true;
    }
    
    function utilizationScaled(address _token) external view returns(uint256) {
        return poolInfo[_token].utilizationScaled;
    }
    
    function getMaxLeverage(address _token) external view returns(uint256) {
        return poolInfo[_token].maxLeverage;
    }
    
    function getPool(address _token) external view returns(address) {
        return poolInfo[_token].ethAddr;
    }
    
    function allPoolsLength() external view returns (uint256) {
        return allPools.length;
    }

    function createPool(address _token) public returns (address) {
        require(allowed[_token] == true, 'POOL_NOT_ALLOWED');
        require(poolInfo[_token].ethAddr == address(0), 'POOL_ALREADY_CREATED');
        address pool;
        bytes memory bytecode = type(UniMexPool).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_token));
        assembly {
            pool := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        UniMexPool(pool).initialize(_token, WETH);
        poolInfo[_token].ethAddr = pool;
        allPools.push(pool);
        emit OnPoolCreated(_token, pool, allPools.length);
        return pool;
    }

}
