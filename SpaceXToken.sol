// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SpaceXToken is ERC20, Ownable {
    constructor() public ERC20("SpaceX Token", "SPACEX") {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function getOwner() external view returns (address) {
        return owner();
    }

}
