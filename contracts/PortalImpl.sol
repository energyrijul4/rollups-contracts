// Copyright (C) 2020 Cartesi Pte. Ltd.

// SPDX-License-Identifier: GPL-3.0-only
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any later
// version.

// This program is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
// PARTICULAR PURPOSE. See the GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

// Note: This component currently has dependencies that are licensed under the GNU
// GPL, version 3, and so you should treat this component as a whole as being under
// the GPL version 3. But all Cartesi-written code in this component is licensed
// under the Apache License, version 2, or a compatible permissive license, and can
// be used independently under the Apache v2 license. After this component is
// rewritten, the entire component will be released under the Apache v2 license.

/// @title Validator Manager
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./Portal.sol";
import "./Input.sol";

contract PortalImpl is Portal {
    address immutable outputContract;
    Input immutable inputContract;

    modifier onlyOutputContract {
        require(msg.sender == outputContract, "only outputContract");
        _;
    }

    constructor(address _inputContract, address _outputContract) {
        inputContract = Input(_inputContract);
        outputContract = _outputContract;
    }

    /// @notice deposits ether in portal contract and create ether in L2
    /// @param _L2receivers array with receivers addresses
    /// @param _amounts array of amounts of ether to be distributed
    /// @param _data information to be interpreted by L2
    /// @return hash of input generated by deposit
    /// @dev  receivers[i] receive amounts[i]
    function etherDeposit(
        address[] calldata _L2receivers,
        uint256[] calldata _amounts,
        bytes calldata _data
    ) public payable override returns (bytes32) {
        require(
            _L2receivers.length == _amounts.length,
            "receivers.len != amounts.len"
        );

        uint256 totalAmount;
        uint256 i;
        for (; i < _amounts.length; i++) {
            totalAmount = totalAmount + _amounts[i];
        }
        require(msg.value >= totalAmount, "not enough value");

        bytes memory input =
            abi.encode(operation.EtherOp, _L2receivers, _amounts, _data);

        emit EtherDeposited(_L2receivers, _amounts, _data);
        return inputContract.addInput(input);
    }

    /// @notice deposits ERC20 in portal contract and create tokens in L2
    /// @param _ERC20 address of ERC20 token to be deposited
    /// @param _L1Sender address on L1 that authorized the transaction
    /// @param _L2receivers array with receivers addresses
    /// @param _amounts array of amounts of ether to be distributed
    /// @param _data information to be interpreted by L2
    /// @return hash of input generated by deposit
    /// @dev  receivers[i] receive amounts[i]
    function erc20Deposit(
        address _ERC20,
        address _L1Sender,
        address[] calldata _L2receivers,
        uint256[] calldata _amounts,
        bytes calldata _data
    ) public override returns (bytes32) {
        require(
            _L2receivers.length == _amounts.length,
            "receivers.len != amounts.len"
        );

        uint256 totalAmount;
        uint256 i;
        for (; i < _amounts.length; i++) {
            totalAmount = totalAmount + _amounts[i];
        }

        IERC20 token = IERC20(_ERC20);

        require(
            token.transferFrom(_L1Sender, address(this), totalAmount),
            "erc20 transferFrom failed"
        );

        bytes memory input =
            abi.encode(
                operation.ERC20Op,
                _L1Sender,
                _L2receivers,
                _amounts,
                _data
            );

        emit ERC20Deposited(_ERC20, _L1Sender, _L2receivers, _amounts, _data);
        return inputContract.addInput(input);
    }

    /// @notice executes a descartesV2 output
    /// @param _data data with information necessary to execute output
    /// @return status of output execution
    /// @dev can only be called by Output contract
    function executeDescartesV2Output(bytes calldata _data)
        public
        override
        onlyOutputContract
        returns (bool)
    {
        // TODO: should use assembly to figure out where the first
        //       relevant word of _data begins and figure out the type
        //       of operation. That way we don't have to encode wasteful
        //       information on data (i.e tokenAddr for ether transfer)
        (
            operation op,
            address tokenAddr,
            address payable receiver,
            uint256 value
        ) = abi.decode(_data, (operation, address, address, uint256));

        if (op == operation.EtherOp) {
            return etherWithdrawal(receiver, value);
        }

        if (op == operation.ERC20Op) {
            return erc20Withdrawal(tokenAddr, receiver, value);
        }

        // operation is not supported
        return false;
    }

    /// @notice withdrawal ether
    /// @param _receiver array with receivers addresses
    /// @param _amount array of amounts of ether to be distributed
    /// @return status of withdrawal
    function etherWithdrawal(address payable _receiver, uint256 _amount)
        internal
        returns (bool)
    {
        // transfer reverts on failure
        _receiver.transfer(_amount);

        emit EtherWithdrawn(_receiver, _amount);
        return true;
    }

    /// @notice withdrawal ERC20
    /// @param _ERC20 address of ERC20 token to be deposited
    /// @param _receiver array with receivers addresses
    /// @param _amount array of amounts of ether to be distributed
    /// @return status of withdrawal
    function erc20Withdrawal(
        address _ERC20,
        address payable _receiver,
        uint256 _amount
    ) internal returns (bool) {
        IERC20 token = IERC20(_ERC20);

        // transfer reverts on failure
        token.transfer(_receiver, _amount);

        emit ERC20Withdrawn(_ERC20, _receiver, _amount);
        return true;
    }
}
