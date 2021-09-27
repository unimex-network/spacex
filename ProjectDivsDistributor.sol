// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ProjectDivsDistributor is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address[] public addresses;
    uint256[] public percents;
    uint256 constant FACTOR = 1e4;

    event WeiDistribution(uint256 amount);
    event TokenDistribution(address token, uint256 amount);
    event UpdateDistributions(address[] addresses, uint256[] percents);

    constructor(address[] memory _addresses, uint256[] memory _percents) public {
        setDistribution(_addresses, _percents);
    }

    function distributeToken(IERC20 token) virtual public {
        require(address(token) != address(0), "zero token");
        uint256 toDistribute = token.balanceOf(address(this));
        if(toDistribute > 0) {
            for(uint256 i = 0; i < addresses.length - 1; i++) {
                token.safeTransfer(addresses[i], toDistribute.mul(percents[i]).div(FACTOR));
            }
            //send rest to the last address (avoid rounding errors)
            token.safeTransfer(addresses[addresses.length - 1], token.balanceOf(address(this)));
        }
        emit TokenDistribution(address(token), toDistribute);
    }

    function distributeWei() external {
        uint256 toDistribute = address(this).balance;
        require(toDistribute > 0, "no balance");
        if(toDistribute > 0) {
            for(uint256 i = 0; i < addresses.length - 1; i++) {
                payable(addresses[i]).transfer(toDistribute.mul(percents[i]).div(FACTOR));
            }
            //send rest to the last address (avoid rounding errors)
            payable(addresses[addresses.length - 1]).transfer(address(this).balance);
        }
        emit WeiDistribution(toDistribute);
    }

    function setDistribution(address[] memory _addresses, uint256[] memory _percents) public onlyOwner {
        require(_addresses.length == _percents.length, "wrong data");
        require(_addresses.length > 0, "no data");
        uint256 sum = 0;
        for(uint i = 0; i < _percents.length; i++) {
            sum += _percents[i];
            require(_addresses[i] != address(0), "zero address");
        }
        require(sum == FACTOR, "wrong percents");
        addresses = _addresses;
        percents = _percents;

        emit UpdateDistributions(_addresses, _percents);
    }

    fallback() payable external {} //receive wei

    receive() payable external {}

}