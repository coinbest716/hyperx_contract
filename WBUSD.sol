// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WBUSD is ERC20 {
    constructor() ERC20("Wrapped BUSD", "WBUSD") {
        _mint(msg.sender, 10 ** 30);
    }
}

contract WHyperXToken is ERC20 {
    constructor() ERC20("Wrapped HyperX Token", "WHyperX") {
        _mint(msg.sender, 10 ** 20);
    }

    function decimals() public view virtual override returns (uint8) {
        return 7;
    }
}

contract CustomToken is ERC20 {
    constructor() ERC20("Custom Token", "CT") {
        _mint(msg.sender, 10 ** 20);
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }
}
