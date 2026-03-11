// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IAresProposalManager {
    function proposals(
        uint256 id
    )
        external
        view
        returns (
            address proposer,
            address target,
            uint256 value,
            bytes memory data,
            uint256 createdAt
        );
}
