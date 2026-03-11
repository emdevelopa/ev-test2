// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library MinimalMerkle {
    function verify(bytes32[] calldata proof, bytes32 root, bytes32 leaf) internal pure returns (bool) {
        bytes32 computedHash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            if (computedHash <= proofElement) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }
        return computedHash == root;
    }
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
}

// scalable reward distribution module
contract AresRewards {
    IERC20 public immutable rewardToken;
    address public immutable treasury;
    
    bytes32 public merkleRoot;
    
    mapping(uint256 => uint256) private claimedBitMap;
    
    event Claimed(address indexed account, uint256 amount, uint256 index);
    event RootUpdated(bytes32 newRoot);
    
    error AlreadyClaimed();
    error InvalidProof();
    error OnlyTreasury();
    
    constructor(address _rewardToken, address _treasury) {
        rewardToken = IERC20(_rewardToken);
        treasury = _treasury;
    }
    
    function isClaimed(uint256 index) public view returns (bool) {
        uint256 wordIndex = index / 256;
        uint256 bitIndex = index % 256;
        uint256 mask = 1 << bitIndex;
        return claimedBitMap[wordIndex] & mask != 0;
    }
    
    function _setClaimed(uint256 index) private {
        uint256 wordIndex = index / 256;
        uint256 bitIndex = index % 256;
        uint256 mask = 1 << bitIndex;
        claimedBitMap[wordIndex] |= mask;
    }
    
    function claim(uint256 index, uint256 amount, bytes32[] calldata merkleProof) external {
        if (isClaimed(index)) revert AlreadyClaimed();
        
        bytes32 node = keccak256(abi.encodePacked(index, msg.sender, amount));
        if (!MinimalMerkle.verify(merkleProof, merkleRoot, node)) revert InvalidProof();
        
        _setClaimed(index);
        
        require(rewardToken.transfer(msg.sender, amount), "Transfer failed");
        
        emit Claimed(msg.sender, amount, index);
    }
    
    function updateRoot(bytes32 newRoot) external {
        if (msg.sender != treasury) revert OnlyTreasury(); // Only through governance execution via treasury
        merkleRoot = newRoot;
        emit RootUpdated(newRoot);
    }
}
