// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./SafeSpaceXTimelock.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SafeTimelockAdmin is Ownable {
    using SafeMath for uint256;

    string private constant SET_DEV_PERCENT_SIG = "set(uint256,uint256,uint16,uint16,bool)";
    string private constant ADD_DEV_PERCENT_SIG = "add(uint256,address,uint16,uint16,bool)";
    string private constant SET_PENDING_ADMIN_SIG = "setPendingAdmin(address)";
    string private constant TRANSFER_OWNERSHIP_SIG = "transferOwnership(address)";

    SafeSpaceXTimelock public immutable timelock;

    modifier withinLimits(string memory signature, bytes memory data) {
      if (bytes4(keccak256(bytes(signature))) == bytes4(keccak256(bytes(SET_DEV_PERCENT_SIG)))) {
        (,,,uint16 withdrawFee,) = abi.decode(data, (uint256,uint256,uint16,uint16,bool));
        require(withdrawFee <= 100, "withdraw fee exceeds max"); //max 1%
      } 

      if (bytes4(keccak256(bytes(signature))) == bytes4(keccak256(bytes(ADD_DEV_PERCENT_SIG)))) {
        (,,,uint16 withdrawFee,) = abi.decode(data, (uint256,address,uint16,uint16,bool));
        require(withdrawFee <= 100, "withdraw fee exceeds max"); //max 1%
      } 

      if (bytes4(keccak256(bytes(signature))) == bytes4(keccak256(bytes(TRANSFER_OWNERSHIP_SIG)))) {
        revert("transferring ownership not allowed");
      } 

      if (bytes4(keccak256(bytes(signature))) == bytes4(keccak256(bytes(SET_PENDING_ADMIN_SIG)))) {
        revert("transferring admin not allowed");
      } 

      _;
    }

    constructor(SafeSpaceXTimelock _timelock) public {
	    require(address(_timelock) != address(0), "zero address");
		timelock = _timelock;
    }

	function queueTransaction(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 eta
    ) public withinLimits(signature, data) onlyOwner returns (bytes32) {
		return timelock.queueTransaction(target, value, signature, data, eta);
    }


    function cancelTransaction(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 eta
    ) onlyOwner public {
		timelock.cancelTransaction(target, value, signature, data, eta);
    }

    function executeTransaction(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 eta
    ) public onlyOwner payable returns (bytes memory) {
		return timelock.executeTransaction(target, value, signature, data, eta);
    }

	function acceptAdmin() external onlyOwner {
		timelock.acceptAdmin();
	}

}