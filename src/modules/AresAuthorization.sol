// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../libraries/SignatureValidator.sol";
import "../interfaces/IAresTimelock.sol";
import "../interfaces/IAresProposalManager.sol";

contract AresAuthorization {
    bytes32 public immutable DOMAIN_SEPARATOR;
    IAresTimelock public immutable timelock;
    IAresProposalManager public immutable proposalManager;
    address public immutable authorizer;  
    
    mapping(uint256 => bool) public authorizedProposals;
    mapping(address => uint256) public nonces;
    
    event ProposalAuthorized(uint256 indexed proposalId);
    
    error InvalidSignature();
    error AlreadyAuthorized();
    error InvalidProposal();
    
    constructor(address _timelock, address _proposalManager, address _authorizer) {
        DOMAIN_SEPARATOR = SignatureValidator.getDomainSeparator("AresAuthorization", "1", address(this));
        timelock = IAresTimelock(_timelock);
        proposalManager = IAresProposalManager(_proposalManager);
        authorizer = _authorizer;
    }
    
    function authorizeProposal(uint256 proposalId, uint8 v, bytes32 r, bytes32 s) external {
        if (authorizedProposals[proposalId]) revert AlreadyAuthorized();
        
        (, address target, uint256 value, bytes memory data, uint256 createdAt) = proposalManager.proposals(proposalId);
        if (createdAt == 0) revert InvalidProposal();
        
        uint256 currentNonce = nonces[authorizer];
        
        address recovered = SignatureValidator.recoverSigner(DOMAIN_SEPARATOR, proposalId, currentNonce, v, r, s);
        if (recovered != authorizer || recovered == address(0)) revert InvalidSignature();
        
        nonces[authorizer]++;
        authorizedProposals[proposalId] = true;
        
        bytes32 globalProposalId = keccak256(abi.encodePacked(proposalId, address(this)));
        timelock.queueProposal(globalProposalId, target, value, data);
        
        emit ProposalAuthorized(proposalId);
    }
}
