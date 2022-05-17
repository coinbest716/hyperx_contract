// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IHyperXNFTFactory {

    /**
     * @dev enumeration for ERC721, ERC1155
     */

    enum CollectionType {
        ERC721,
        ERC1155
    }

    /**
     * @dev Emitted when a new NFT collection is created.
     */
    event NewCollectionCreated(CollectionType collectionType, address indexed to);

    /**
     * @dev Emitted when an old NFT collection is added.
     */
    event CollectionAdded(CollectionType collectionType, address indexed from);

    /**
     * @dev Create a new NFT collection of 'collectionType'
     */
    function createNewCollection(CollectionType collectionType, 
                                string memory _name,
                                string memory _symbol,
                                string memory _uri) 
        external returns (address);
    
    /**
     * @dev Create a new NFT collection of 'collectionType'
     */
     function addCollection(address from) external;
}
