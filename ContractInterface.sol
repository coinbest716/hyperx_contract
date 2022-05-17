// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IContractInterface721 {
    /**
     * event when an ERC721 contract is created
     */
    event CreatedERC721TradableContract(address indexed factory, address indexed newContract);

    /**
     * this function is called to create an ERC721 contract.
     */
    function createContract(
        string memory _name,
        string memory _symbol,
        string memory _uri,
        address factory
    ) external returns (address);
}

interface IContractInterface1155 {
    /**
     * event when an ERC1155 contract is created
     */
    event CreatedERC1155TradableContract(address indexed factory, address indexed newContract);

    /**
     * this function is called to create an ERC1155 contract.
     */
    function createContract(
        string memory _name,
        string memory _symbol,
        string memory _uri,
        address factory
    ) external returns (address);
}

interface IContractInfoWrapper {
    /**
     * this function is called to get token URI.
     */
    function tokenURI(uint256 _tokenId) external view returns (string memory);
    /**
     * this function is called to get a creator of the token
     */
    function getCreator(uint256 _id) external view returns(address);
    /**
     * this function is called to get token URI.
     */
    function uri(uint256 _id) external view returns (string memory);
}
