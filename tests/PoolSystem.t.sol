// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {AddressesRegistry} from "../reference/bold/contracts/src/AddressesRegistry.sol";
import {ActivePool} from "../reference/bold/contracts/src/ActivePool.sol";
import {DefaultPool} from "../reference/bold/contracts/src/DefaultPool.sol";
import {CollSurplusPool} from "../reference/bold/contracts/src/CollSurplusPool.sol";
import {GasPool} from "../reference/bold/contracts/src/GasPool.sol";
import {BoldToken} from "../reference/bold/contracts/src/BoldToken.sol";
import {TroveChange} from "../reference/bold/contracts/src/Types/TroveChange.sol";
import {ActiveCollateralToken,RewardsRecorder,TimeVm} from "./ActivePoolParity.t.sol";
import {PoolVm} from "./DefaultPoolParity.t.sol";
contract PoolSystemTest {
    PoolVm constant vm=PoolVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address constant ALICE=address(0xa11ce);
    address constant ROUTER=address(0x100);
    struct System {
        AddressesRegistry registry;
        ActivePool active;
        DefaultPool defaults;
        CollSurplusPool surplus;
        BoldToken bold;
        ActiveCollateralToken coll;
        RewardsRecorder sp;
        address gasPool;
    }
    function code(string memory name,bool fe) internal view returns(bytes memory) {
        if(fe) return vm.parseBytes(vm.readFile(string.concat("build/",name,".bin")));
        bytes32 key=keccak256(bytes(name));
        if(key==keccak256("AddressesRegistry"))return type(AddressesRegistry).creationCode;
        if(key==keccak256("ActivePool"))return type(ActivePool).creationCode;
        if(key==keccak256("DefaultPool"))return type(DefaultPool).creationCode;
        if(key==keccak256("CollSurplusPool"))return type(CollSurplusPool).creationCode;
        if(key==keccak256("BoldToken"))return type(BoldToken).creationCode;
        if(key==keccak256("GasPool"))return type(GasPool).creationCode;
        revert("unknown code");
    }
    function predict(bytes memory init) internal view returns(address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(hex"ff",address(this),bytes32(0),keccak256(init))))));
    }
    function deploy(bytes memory init) internal returns(address target) {
        assembly {target:=create2(0,add(init,32),mload(init),0)}
        require(target.code.length>0,"system deployment");
    }
    function make(bool fe) internal returns(System memory s) {
        s.coll=new ActiveCollateralToken();s.sp=new RewardsRecorder();
        s.registry=AddressesRegistry(deploy(bytes.concat(code("AddressesRegistry",fe),abi.encode(address(this),15e17,11e17,1e17,11e17,5e16,1e17))));
        s.bold=BoldToken(deploy(bytes.concat(code("BoldToken",fe),abi.encode(address(this)))));
        bytes memory activeInit=bytes.concat(code("ActivePool",fe),abi.encode(s.registry));
        bytes memory defaultInit=bytes.concat(code("DefaultPool",fe),abi.encode(s.registry));
        bytes memory surplusInit=bytes.concat(code("CollSurplusPool",fe),abi.encode(s.registry));
        bytes memory gasInit=bytes.concat(code("GasPool",fe),abi.encode(s.registry));
        address[18] memory vars;
        vars[0]=address(s.coll);vars[1]=address(this);vars[2]=address(this);vars[5]=address(s.sp);
        vars[7]=predict(activeInit);vars[8]=predict(defaultInit);vars[9]=predict(gasInit);vars[10]=predict(surplusInit);
        vars[12]=ROUTER;vars[15]=address(this);vars[16]=address(s.bold);vars[17]=address(s.coll);
        (bool ok,)=address(s.registry).call(abi.encodePacked(AddressesRegistry.setAddresses.selector,abi.encode(vars)));require(ok,"set addresses");
        s.active=ActivePool(deploy(activeInit));s.defaults=DefaultPool(deploy(defaultInit));
        s.surplus=CollSurplusPool(deploy(surplusInit));s.gasPool=deploy(gasInit);
        s.bold.setBranchAddresses(address(this),address(s.sp),address(this),address(s.active));
        s.bold.setCollateralRegistry(address(this));
        require(s.registry.owner()==address(0)&&s.bold.owner()==address(0));
        require(s.coll.allowance(s.gasPool,address(this))==type(uint256).max);
    }
    function run(System memory s) internal returns(uint256[12] memory out) {
        s.coll.mint(address(this),100e18);s.coll.approve(address(s.active),type(uint256).max);
        s.active.receiveColl(100e18);
        TroveChange memory c;c.debtIncrease=2000e18;c.newWeightedRecordedDebt=2000e18*5e16;c.upfrontFee=7e18;
        s.active.mintAggInterestAndAccountForTroveChange(c,address(0));s.bold.mint(ALICE,2000e18);
        // Move a debt/collateral slice to the redistribution pool.
        s.active.sendCollToDefaultPool(20e18);s.defaults.increaseBoldDebt(200e18);
        c.debtIncrease=0;c.debtDecrease=200e18;c.upfrontFee=0;
        c.oldWeightedRecordedDebt=2000e18*5e16;c.newWeightedRecordedDebt=1800e18*5e16;
        s.active.mintAggInterestAndAccountForTroveChange(c,address(0));
        require(s.active.getCollBalance()==80e18&&s.defaults.getCollBalance()==20e18);
        // Apply that redistribution to an active trove.
        s.defaults.sendCollToActivePool(20e18);s.defaults.decreaseBoldDebt(200e18);
        c.debtDecrease=0;c.appliedRedistBoldDebtGain=200e18;c.oldWeightedRecordedDebt=1800e18*5e16;c.newWeightedRecordedDebt=2000e18*5e16;
        s.active.mintAggInterestAndAccountForTroveChange(c,address(0));
        require(s.defaults.getBoldDebt()==0&&s.defaults.getCollBalance()==0);
        require(s.coll.balanceOf(address(s.active))==100e18);
        // Send collateral surplus through its real authorization and claim path.
        s.active.sendColl(address(s.surplus),3e18);s.surplus.accountSurplus(ALICE,3e18);s.surplus.claimColl(ALICE);
        require(s.surplus.getCollateral(ALICE)==0&&s.coll.balanceOf(ALICE)==3e18);
        TimeVm(address(vm)).warp(block.timestamp+365 days);s.active.mintAggInterest();
        out=[s.active.getCollBalance(),s.active.getBoldDebt(),s.active.aggRecordedDebt(),s.bold.totalSupply(),s.bold.balanceOf(ALICE),s.bold.balanceOf(ROUTER),s.bold.balanceOf(address(s.sp)),s.sp.rewards(address(s.active)),s.coll.balanceOf(ALICE),s.coll.balanceOf(address(s.active)),s.defaults.getBoldDebt(),s.surplus.getCollBalance()];
        require(out[1]==2107e18&&out[3]==2107e18,"supply and recorded debt");
        require(out[5]==107e18/4&&out[6]==107e18*3/4&&out[7]==out[6],"real BOLD yield");
    }
    function testConnectedPoolsAndBoldMatchReference() public {
        TimeVm(address(vm)).warp(1000);System memory fe=make(true);uint256[12] memory actual=run(fe);
        TimeVm(address(vm)).warp(1000);System memory sol=make(false);uint256[12] memory expected=run(sol);
        require(keccak256(abi.encode(actual))==keccak256(abi.encode(expected)),"system state parity");
    }
}
