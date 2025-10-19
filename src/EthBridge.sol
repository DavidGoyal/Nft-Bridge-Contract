// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IERC721Burnable is IERC721 {
    function burn(uint256 tokenId) external;
}

interface ERC721SeaDropCloneable {
    function burn(uint256 tokenId) external;
}

contract EthBridge is Ownable, Pausable, ReentrancyGuard{
    error InvalidNftAddress();
    error InvalidOwner();
    error InsufficientPayment();
    error CollectionNotApproved();
    error InvalidRecipient();

    enum BurnType {
        ERC721Burnable,
        SeaDrop,
        TransferToZeroAddress,
        TransferToRecipient
    }
    
    struct CollectionInfo{
        uint256 bridgeCost;
        BurnType burnType;
        address recipient;
    }

    mapping (address=>bool) public approvedAddresses;
    mapping (address=>CollectionInfo) public collectionInfo;
    mapping(address=>mapping (address=>uint256[])) public depositedNfts;

    event Deposit(address indexed nftAddress,address indexed sender, uint256 tokenId);

    function pause() external onlyOwner{
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    modifier isCollectionApproved(address nftAddress){
        if(approvedAddresses[nftAddress] == false) revert CollectionNotApproved();
        _;
    }

    constructor() Ownable(msg.sender) Pausable(){}

    function setApprovedCollectionAddresses(address nftAddress) 
        external 
        onlyOwner
    {
        if(nftAddress==address(0)) revert InvalidNftAddress();
        approvedAddresses[nftAddress] = true;
    }

    function setCollectionInfo(address nftAddress,uint256 _bridgeCost, BurnType _burnType, address _recipient) 
        external 
        isCollectionApproved(nftAddress) 
        onlyOwner
    {
        if(_burnType == BurnType.TransferToRecipient && _recipient == address(0)) revert InvalidRecipient();
        collectionInfo[nftAddress]=CollectionInfo(
            _bridgeCost,
            _burnType,
            _recipient
        );
    }

    function deposit(address nftAddress, uint256 tokenId) 
        external 
        payable    
        isCollectionApproved(nftAddress)
        whenNotPaused
        nonReentrant
    {
        uint256 bridgeCost=collectionInfo[nftAddress].bridgeCost;
        BurnType burnType=collectionInfo[nftAddress].burnType;

        if(IERC721(nftAddress).ownerOf(tokenId)!=msg.sender) revert InvalidOwner();
        if(msg.value<bridgeCost) revert InsufficientPayment();

        depositedNfts[nftAddress][msg.sender].push(tokenId);

        if(burnType == BurnType.ERC721Burnable){
            IERC721Burnable(nftAddress).burn(
                tokenId
            );
        }
        else if(burnType == BurnType.SeaDrop){
            ERC721SeaDropCloneable(nftAddress).burn(
                tokenId
            );
        }
        else if(burnType == BurnType.TransferToZeroAddress){
            IERC721(nftAddress).transferFrom(msg.sender,address(0),tokenId);
        }
        else{
            IERC721(nftAddress).transferFrom(msg.sender,collectionInfo[nftAddress].recipient,tokenId);
        }

        emit Deposit(nftAddress,msg.sender, tokenId);
    }

    function getDepositedNfts(address _nftAddress,address _owner) 
        external 
        view 
        returns(uint256[] memory)
    {
        return depositedNfts[_nftAddress][_owner];
    }

    function withdrawFunds(address _fundsReceiver) external onlyOwner{
        (bool success, ) = payable(_fundsReceiver).call{value: address(this).balance}('');
        require(success,"Transfer Failed");
    }
}