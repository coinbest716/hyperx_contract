// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ContractInterface.sol";
import "./ERC721Tradable.sol";

contract ContractInterface721 is IContractInterface721 {
    constructor() {}

    function createContract(
        string memory _name,
        string memory _symbol,
        string memory _uri,
        address factory
    ) external override returns (address) {
        ERC721Tradable tCon721 = new ERC721Tradable(
            _name,
            _symbol,
            _uri,
            factory
        );

        tCon721.transferOwnership(factory);

        emit CreatedERC721TradableContract(factory, address(tCon721));
        return address(tCon721);
    }
}
