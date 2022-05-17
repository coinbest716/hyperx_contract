// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./common/meta-transactions/ContextMixin.sol";
import "./common/meta-transactions/NativeMetaTransaction.sol";

/**
 * @title ERC1155Tradable
 * ERC1155Tradable - ERC1155 contract that whitelists an operator address, has create and mint functionality, and supports useful standards from OpenZeppelin,
  like _exists(), name(), symbol(), and totalSupply()
 */
contract ERC1155Tradable is
    ContextMixin,
    ERC1155,
    NativeMetaTransaction,
    Ownable
{
    using Strings for string;
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    /**
     0xd9b67a26 = type(IERC1155).interfaceId =   bytes4(keccak256("balanceOf(address,uint256)")) 
                                            ^   bytes4(keccak256("balanceOfBatch(address[],uint256[])"))
                                            ^   bytes4(keccak256("setApprovalForAll(address,bool)"))
                                            ^   bytes4(keccak256("isApprovedForAll(address,address)"))
                                            ^   bytes4(keccak256("safeTransferFrom(address,address,uint256,uint256,bytes)"))
                                            ^   bytes4(keccak256("safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)"))
     */
    bytes4 internal constant INTERFACE_ERC1155 = 0xd9b67a26;

    // Role management
    mapping(uint256 => address) private creators;
    // total supply of the token with respect to its id
    mapping(uint256 => uint256) private tokenSupply;
    // token URI with respect to its id
    mapping(uint256 => string) private customUri;
    // count of holders with respect to its id
    mapping(uint256 => Counters.Counter) private holderCount;
    // Contract name
    string public name;
    // Contract symbol
    string public symbol;

    //factory address
    address public factory;
    // reserved token id to be minted
    Counters.Counter _nextTokenId;

    // changed creator of tokenId
    event CreatorSet(address indexed account, uint256 tokenId);
    // event to change the factory contract
    event SetFactoryContract(address indexed _factory);

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _uri,
        address _factory
    ) ERC1155(_uri) {
        name = _name;
        symbol = _symbol;
        _initializeEIP712(name);
        factory = _factory;

        _nextTokenId.increment();
    }

    function uri(uint256 _id) public view override returns (string memory) {
        require(_exists(_id));
        // We have to convert string to bytes to check for existence
        bytes memory customUriBytes = bytes(customUri[_id]);
        if (customUriBytes.length > 0) {
            return customUri[_id];
        } else {
            return
                string(abi.encodePacked(super.uri(_id), Strings.toString(_id)));
        }
    }

    /**
     * @dev Returns the total quantity for a token ID
     * @param _id uint256 ID of the token to query
     * @return amount of token in existence
     */
    function totalSupply(uint256 _id) public view returns (uint256) {
        return tokenSupply[_id];
    }

    /**
     * @dev Returns the count of holders for a token ID
     * @param _id uint256 ID of the token to query
     * @return count of token holders
     */
    function holders(uint256 _id) public view returns (uint256) {
        return holderCount[_id].current();
    }

    /**
     * @dev Sets a new URI for all token types, by relying on the token type ID
     * substitution mechanism
     * https://eips.ethereum.org/EIPS/eip-1155#metadata[defined in the EIP].
     * @param _newURI New URI for all tokens
     */
    function setURI(string memory _newURI) public onlyOwner {
        _setURI(_newURI);
    }

    /**
     * @dev Will update the base URI for the token
     * @param _tokenId The token to update. _msgSender() must be its creator.
     * @param _newURI New URI for the token.
     */
    function setCustomURI(
        address issuer,
        uint256 _tokenId,
        string memory _newURI
    ) public onlyOwner {
        require(creators[_tokenId] == issuer);

        customUri[_tokenId] = _newURI;
        emit URI(_newURI, _tokenId);
    }

    /**
     * @dev returns the token id to be minted as a new token
     */

    function getReservedTokenId() public view returns (uint256) {
        return _nextTokenId.current();
    }

    /**
     * @dev Creates a new token type and assigns _initialSupply to an address
     * NOTE: remove onlyOwner if you want third parties to create new tokens on
     *       your contract (which may change your IDs)
     * NOTE: The token id must be passed. This allows lazy creation of tokens or
     *       creating NFTs by setting the id's high bits with the method
     *       described in ERC1155 or to use ids representing values other than
     *       successive small integers. If you wish to create ids as successive
     *       small integers you can either subclass this class to count onchain
     *       or maintain the offchain cache of identifiers recommended in
     *       ERC1155 and calculate successive ids from that.
     * @param _initialOwner address of the first owner of the token
     * @param _initialSupply amount to supply the first owner
     * @param _uri Optional URI for this token type
     * @param _data Data to pass if receiver is contract
     * @return The newly created token ID
     */
    function create(
        address _initialOwner,
        uint256 _initialSupply,
        string memory _uri,
        bytes memory _data
    ) public onlyOwner returns (uint256) {
        uint256 _id = _nextTokenId.current();
        _nextTokenId.increment();

        require(!_exists(_id));

        uint256 [] memory ids = new uint256[](1);
        ids[0] = _id;
        setCreator(_initialOwner, ids);

        if (bytes(_uri).length > 0) {
            customUri[_id] = _uri;
            emit URI(_uri, _id);
        }

        _mint(_initialOwner, _id, _initialSupply, _data);
        return _id;
    }

    /**
     * @dev Mints some amount of tokens to an address
     * @param _to          Address of the future owner of the token
     * @param _id          Token ID to mint
     * @param _quantity    Amount of tokens to mint
     * @param _data        Data to pass if receiver is contract
     */
    function mint(
        address _to,
        uint256 _id,
        uint256 _quantity,
        bytes memory _data
    ) public virtual onlyOwner {
        require(creators[_id] == _to);

        _mint(_to, _id, _quantity, _data);
    }

    /**
     * @dev Mint tokens for each id in _ids
     * @param _to          The address to mint tokens to
     * @param _ids         Array of ids to mint
     * @param _quantities  Array of amounts of tokens to mint per id
     * @param _data        Data to pass if receiver is contract
     */
    function batchMint(
        address _to,
        uint256[] memory _ids,
        uint256[] memory _quantities,
        bytes memory _data
    ) public onlyOwner {
        for (uint256 i = 0; i < _ids.length; i++) {
            uint256 _id = _ids[i];
            require(creators[_id] == _to);
        }
        _mintBatch(_to, _ids, _quantities, _data);
    }

    /**
     * @dev Change the creator address for given tokens
     * @param _to   Address of the new creator
     * @param _ids  Array of Token IDs to change creator
     */
    function setCreator(address _to, uint256[] memory _ids) public onlyOwner {
        require(_to != address(0));

        for (uint256 i = 0; i < _ids.length; i++) {
            uint256 id = _ids[i];
            _setCreator(_to, id);
        }
    }

    /**
     * @dev Change the creator address for given token
     * @param _to   Address of the new creator
     * @param _id  Token IDs to change creator of
     */
    function _setCreator(address _to, uint256 _id) internal {
        creators[_id] = _to;
        emit CreatorSet(_to, _id);
    }

    /**
     * @dev Change the creator address for given token
     * @param _id - token index
     */
    function getCreator(uint256 _id) public view returns(address) {
        return creators[_id];
    }

    /**
     * @dev Returns whether the specified token exists by checking to see if it has a creator
     * @param _id uint256 ID of the token to query the existence of
     * @return bool whether the token exists
     */
    function _exists(uint256 _id) internal view returns (bool) {
        return creators[_id] != address(0);
    }

    function exists(uint256 _id) external view returns (bool) {
        return _exists(_id);
    }

    /**
     * This is used instead of msg.sender as transactions won't be sent by the original token owner, but by OpenSea.
     */
    function _msgSender() internal view override returns (address sender) {
        return ContextMixin.msgSender();
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting
     * and burning, as well as batched variants.
     *
     * The same hook is called on both single and batched variants. For single
     * transfers, the length of the `id` and `amount` arrays will be 1.
     *
     * Calling conditions (for each `id` and `amount` pair):
     *
     * - When `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * of token type `id` will be  transferred to `to`.
     * - When `from` is zero, `amount` tokens of token type `id` will be minted
     * for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens of token type `id`
     * will be burned.
     * - `from` and `to` are never both zero.
     * - `ids` and `amounts` have the same, non-zero length.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory
    ) internal override {
        uint256 i;
        for (i = 0; i < ids.length; i++) {
            uint256 tokenId = ids[i];
            uint256 amount = amounts[i];

            if (to == address(0)) {
                // burn from owner
                if (balanceOf(from, tokenId) == amount) {
                    holderCount[tokenId].decrement();
                }

                // if (tokenSupply[tokenId] == amount) {
                //     creators[tokenId] = address(0);
                // }

                tokenSupply[tokenId] = tokenSupply[tokenId].sub(
                    amount,
                    "tokenSupply insufficient"
                );
            } else if (from == address(0)) {
                // mint to a new owner
                if (balanceOf(to, tokenId) == 0) {
                    holderCount[tokenId].increment();
                }
                tokenSupply[tokenId] = tokenSupply[tokenId].add(amount);
            } else {
                if (from != to) {
                    if (balanceOf(from, tokenId) == amount) {
                        holderCount[tokenId].decrement();
                    }

                    if (balanceOf(to, tokenId) == 0) {
                        holderCount[tokenId].increment();
                    }
                }
            }
        }
    }

    function isApprovedForAll(address account, address operator)
        public
        view
        virtual
        override
        returns (bool)
    {
        if (factory == operator) {
            return true;
        }

        return super.isApprovedForAll(account, operator);
    }

    /**
     * @dev Destroys `amount` tokens of token type `id` from `from`
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `from` must have at least `amount` tokens of token type `id`.
     */
    function burn(
        address from,
        uint256 id,
        uint256 amount
    ) public onlyOwner {
        _burn(from, id, amount);
    }

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {_burn}.
     *
     * Requirements:
     *
     * - `ids` and `amounts` must have the same length.
     */
    function batchBurn(
        address from,
        uint256[] memory ids,
        uint256[] memory amounts
    ) public onlyOwner {
        _burnBatch(from, ids, amounts);
    }

    /**
     * set factory contract address if an owner
     */
    function setFactoryContract(address _factory) external onlyOwner {
        require(factory != _factory);

        factory = _factory;
        emit SetFactoryContract(factory);
    }
}
