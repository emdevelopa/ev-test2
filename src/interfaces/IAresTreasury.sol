// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IAresTreasury {
    function executeTransaction(
        address target,
        uint256 value,
        bytes calldata data
    ) external returns (bytes memory);
    function updateDrainLimit(uint256 newLimit) external;
    function receiveFunds() external payable;
}
