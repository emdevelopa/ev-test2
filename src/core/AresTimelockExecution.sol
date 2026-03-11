// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract AresTimelockExecution {
    uint256 public immutable DELAY;
    address public immutable authorizationModule;
    
    enum ProposalState { Inactive, Queued, Executed, Cancelled }
    
    struct QueuedProposal {
        bytes32 txHash;
        uint256 executeAfter;
        ProposalState state;
    }
    
    mapping(bytes32 => QueuedProposal) public proposals;
    
    // Reentrancy guard
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;
    
    event ProposalQueued(bytes32 indexed proposalId, bytes32 txHash, uint256 executeAfter);
    event ProposalExecuted(bytes32 indexed proposalId);
    event ProposalCancelled(bytes32 indexed proposalId);
    
    error OnlyAuthorizationModule();
    error InvalidState();
    error TimelockNotExpired();
    error ReentrantCall();
    
    modifier nonReentrant() {
        if (_status == _ENTERED) revert ReentrantCall();
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
    
    modifier onlyAuth() {
        if (msg.sender != authorizationModule) revert OnlyAuthorizationModule();
        _;
    }

    constructor(uint256 delay, address _authorizationModule) {
        DELAY = delay;
        authorizationModule = _authorizationModule;
        _status = _NOT_ENTERED;
    }
    
    function queueProposal(bytes32 proposalId, address target, uint256 value, bytes calldata data) external onlyAuth {
        if (proposals[proposalId].state != ProposalState.Inactive) revert InvalidState();
        
        bytes32 txHash = keccak256(abi.encode(target, value, data));
        uint256 executeAfter = block.timestamp + DELAY;
        
        proposals[proposalId] = QueuedProposal({
            txHash: txHash,
            executeAfter: executeAfter,
            state: ProposalState.Queued
        });
        
        emit ProposalQueued(proposalId, txHash, executeAfter);
    }
    
    function executeProposal(bytes32 proposalId, address target, uint256 value, bytes calldata data) external nonReentrant {
        QueuedProposal storage prop = proposals[proposalId];
        
        if (prop.state != ProposalState.Queued) revert InvalidState();
        if (block.timestamp < prop.executeAfter) revert TimelockNotExpired();
        
        bytes32 txHash = keccak256(abi.encode(target, value, data));
        if (prop.txHash != txHash) revert InvalidState();
        
        prop.state = ProposalState.Executed;
        
        (bool success, ) = target.call{value: value}(data);
        require(success, "Execution failed");
        
        emit ProposalExecuted(proposalId);
    }
    
    function cancelProposal(bytes32 proposalId) external onlyAuth {
        if (proposals[proposalId].state != ProposalState.Queued) revert InvalidState();
        proposals[proposalId].state = ProposalState.Cancelled;
        emit ProposalCancelled(proposalId);
    }
}
