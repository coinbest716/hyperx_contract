// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./common/meta-transactions/ContextMixin.sol";
import "./common/meta-transactions/NativeMetaTransaction.sol";

/**
 * @title ERC721Tradable
 * ERC721Tradable - ERC721 contract that whitelists a trading address, and has minting functionality.
 */
contract ERC721Tradable is ERC721, ContextMixin, NativeMetaTransaction, Ownable {
    using SafeMath for uint256;
    using Counters for Counters.Counter; 

    /**
     0x80ac58cd = type(IERC721).interfaceId =   bytes4(keccak256("balanceOf(address)")) 
                                            ^   bytes4(keccak256("ownerOf(uint256)"))
                                            ^   bytes4(keccak256("safeTransferFrom(address,address,uint256)"))
                                            ^   bytes4(keccak256("transferFrom(address,address,uint256)"))
                                            ^   bytes4(keccak256("approve(address,uint256)"))
                                            ^   bytes4(keccak256("getApproved(uint256)"))
                                            ^   bytes4(keccak256("setApprovalForAll(address,bool)"))
                                            ^   bytes4(keccak256("isApprovedForAll(address,address)"))
                                            ^   bytes4(keccak256("safeTransferFrom(address,address,uint256,bytes)"))
     */
    bytes4 constant internal INTERFACE_ERC721 = 0x80ac58cd;

    /**
     * We rely on the OZ Counter util to keep track of the next available ID.
     * We track the nextTokenId instead of the currentTokenId to save users on gas costs. 
     * Read more about it here: https://shiny.mirror.xyz/OUampBbIz9ebEicfGnQf5At_ReMHlZy0tB4glb9xQ0E
     */ 
    Counters.Counter private _nextTokenId;

    // Role management
    mapping(uint256 => address) private creators;
    // token URI mapping per user.
    mapping(uint256 => string) private uriMapping;
    // total count of holders
    Counters.Counter private holderCount;
    Counters.Counter private totalBalance;

    //factory address
    address public factory;

    // base URI for each token
    // tokenURI will be of the format baseURI + tokenId when uriMapping has no valid path
    string private baseURI;

    // event to change the factory contract
    event SetFactoryContract(address indexed _factory);
    // changed creator of tokenId
    event CreatorSet(address indexed account, uint256 tokenId);

    constructor(
        string memory _name,
        string memory _symbol,
        string memory __baseURI,
        address _factory
    ) ERC721(_name, _symbol) {
        // nextTokenId is initialized to 1, since starting at 0 leads to higher gas cost for the first minter
        _nextTokenId.increment();
        holderCount.increment();
        totalBalance.increment();
        // getDomainSeperator() can be used to identify the contract location.
        _initializeEIP712(_name);

        baseURI = __baseURI;
        factory = _factory;
    }

    /**
     * @dev Mints a token to an address with a tokenURI.
     * @param _to address of the future owner of the token
     */
    function mintTo(address _to, string memory uri) public onlyOwner {
        uint256 currentTokenId = _nextTokenId.current();

        // token URI set if valid
        // it is returned in tokenURI() function
        if (bytes(uri).length != 0) {
            uriMapping[currentTokenId] = uri;
        }

        setCreator(_to, currentTokenId);

        _nextTokenId.increment();

        _safeMint(_to, currentTokenId);
    }

    /**
     * @dev Burns a token from the owner.
     * @param _tokenId token index starting at 1.
     */
    function burn(uint256 _tokenId) public onlyOwner {
        _burn(_tokenId);
    }

    /**
     * @dev Change the creator address for given token
     * @param _to   Address of the new creator
     * @param _id   token index
     */
    function setCreator(
        address _to,
        uint256 _id
    ) public onlyOwner {
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
     * @dev Mints a token to an address with a tokenURI.
     * @param   from address of the previous owner of the token
                to address of the new owner of the token
                tokenId index of the token.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        if (to == address(0)) { // burn from owner
            if (balanceOf(from) == 1) {
                holderCount.decrement();
            }

            uriMapping[tokenId] = "";
        } else if (from == address(0)) { // mint to a new owner
            if (balanceOf(to) == 0) {
                holderCount.increment();
            }
            totalBalance.increment();
        } else {
            if (from != to) {
                if (balanceOf(from) == 1) {
                    holderCount.decrement();
                }

                if (balanceOf(to) == 0) {
                    holderCount.increment();
                }
            }
        }
    }

    /**
        @dev Returns the total tokens minted so far.
        1 is always subtracted from the Counter since it tracks the next available tokenId.
     */
    function totalSupply() public view returns (uint256) {
        return totalBalance.current() - 1;
    }

    /**
        @dev Returns the count of total token holders.
     */
    function totalHolders() public view returns (uint256) {
        return holderCount.current() - 1;
    }

    /**
     * @dev Base URI for computing {tokenURI}. If set, the resulting URI for each
     * token will be the concatenation of the `baseURI` and the `tokenId`. Empty
     * by default, can be overriden in child contracts.
     */
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /**
        @dev Returns the URI of the token at "_tokenId"
        @param _tokenId index of the token to be retrieved.
     */
    function tokenURI(uint256 _tokenId) override public view returns (string memory) {
        require(_exists(_tokenId));

        if (bytes(uriMapping[_tokenId]).length > 0) {
            return uriMapping[_tokenId];
        } else {
            return ERC721.tokenURI(_tokenId);
        }
    }

    /**
        @dev Returns validity of the token at "_tokenId"
        @param _tokenId index of the token to be retrieved.
     */
    function hasBurnt(uint256 _tokenId) external view returns (bool) {
        if (_tokenId >= _nextTokenId.current())  {
            return false;
        }

        return !_exists(_tokenId);
    }

    /**
     * @dev returns the token id to be minted as a new token
     */

    function getReservedTokenId() public view returns (uint256) {
        return _nextTokenId.current();
    }

    /**
     * Override isApprovedForAll to whitelist user's OpenSea proxy accounts to enable gas-less listings.
     */
    function isApprovedForAll(address owner, address operator)
        override
        public
        view
        returns (bool)
    {
        if (factory == operator) {
            return true;
        }

        return super.isApprovedForAll(owner, operator);
    }

    /**
     * set factory contract address if an owner
     */
    function setFactoryContract(address _factory) external onlyOwner {
        require(factory != _factory);

        factory = _factory;
        emit SetFactoryContract(factory);
    }

    /**
     * This is used instead of msg.sender as transactions won't be sent by the original token owner, but by OpenSea.
     */
    function _msgSender()
        internal
        override
        view
        returns (address sender)
    {
        return ContextMixin.msgSender();
    }
}
