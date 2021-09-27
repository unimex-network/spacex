// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../unimex/Uniswap.sol";

contract UniswapV2PairMock {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public factory;
    address public token0;
    address public token1;

    uint112 private reserve0;           // uses single storage slot, accessible via getReserves
    uint112 private reserve1;           // uses single storage slot, accessible via getReserves
    uint32  private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint public price0CumulativeLast;
    uint public price1CumulativeLast;

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'UniswapV2: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );

    event OnDebug(
        string message,
        uint256 value
    );

    constructor() public {
        factory = msg.sender;
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function setReserves(uint112 _reserve0, uint112 _reserve1) external {
        reserve0 = _reserve0;
        reserve1 = _reserve1;

        emit OnDebug("set reserve 0", reserve0);
        emit OnDebug("set reserve 1", reserve1);
    }

    function setReservesByTokens(address _tokenA, uint112 _reserveA, address _tokenB, uint112 _reserveB) external {
        (uint112 _reserve0, uint112 _reserve1) = _tokenA < _tokenB ? (_reserveA, _reserveB) : (_reserveB, _reserveA);
        reserve0 = _reserve0;
        reserve1 = _reserve1;

        emit OnDebug("set reserve 0", reserve0);
        emit OnDebug("set reserve 1", reserve1);
    }

    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, 'UniswapV2: FORBIDDEN'); // sufficient check
        token0 = _token0;
        token1 = _token1;
    }
}
