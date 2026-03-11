// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Proposing of changes.
contract AresProposalManager {
    uint256 public proposalCount;
    address public immutable governanceToken;
    uint256 public immutable proposalThreshold;
    
    struct Proposal {
        address proposer;
        address target;
        uint256 value;
        bytes data;
        uint256 createdAt;
    }
    
    mapping(uint256 => Proposal) public proposals;
    
    event ProposalCreated(uint256 indexed id, address indexed proposer, address target, uint256 value, bytes data);
    
    error BelowProposalThreshold();
    
    constructor(address _governanceToken, uint256 _proposalThreshold) {
        governanceToken = _governanceToken;
        proposalThreshold = _proposalThreshold;
    }
    
    function _getVotes(address account) internal view returns (uint256) {
        (bool success, bytes memory data) = governanceToken.staticcall(abi.encodeWithSignature("getVotes(address)", account));
        if (success && data.length == 32) {
            return abi.decode(data, (uint256));
        }
        // Fallback for mock balances
        (success, data) = governanceToken.staticcall(abi.encodeWithSignature("balanceOf(address)", account));
        if (success && data.length == 32) {
            return abi.decode(data, (uint256));
        }
        return 0;
    }
    
    function propose(address target, uint256 value, bytes calldata data) external returns (uint256) {
        if (_getVotes(msg.sender) < proposalThreshold) revert BelowProposalThreshold();
        
        uint256 id = ++proposalCount;
        proposals[id] = Proposal({
            proposer: msg.sender,
            target: target,
            value: value,
            data: data,
            createdAt: block.timestamp
        });
        
        emit ProposalCreated(id, msg.sender, target, value, data);
        return id;
    }
}
