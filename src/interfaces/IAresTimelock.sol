// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IAresTimelock {
    function queueProposal(bytes32 proposalId, address target, uint256 value, bytes calldata data) external;
}
