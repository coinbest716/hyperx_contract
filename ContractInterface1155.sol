// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ContractInterface.sol";
import "./ERC1155Tradable.sol";
// import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract ContractInterface1155 is IContractInterface1155 {
    constructor() {}

    function createContract(
        string memory _name,
        string memory _symbol,
        string memory _uri,
        address factory
    ) external override returns (address) {
        ERC1155Tradable tCon1155 = new ERC1155Tradable(
                _name,
                _symbol,
                _uri,
                factory
            );

        tCon1155.transferOwnership(factory);

        emit CreatedERC1155TradableContract(factory, address(tCon1155));
        return address(tCon1155);
    }
}
