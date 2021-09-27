// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;

interface IUniMexPool {
    function borrow(uint256 _amount) external;
    function distribute(uint256 _amount) external;
    function repay(uint256 _amount) external returns (bool);
    function deposit(uint256 _amount) external returns (bool);
    function withdraw(uint256 _amount) external returns (bool);
    function claim() external returns (bool);
    function dividendsOf(address _user) external view returns (uint256);
    function balanceOf(address _user) external view returns (uint256);
    function correctedBalanceOf(address _user) external view returns (uint256);
}