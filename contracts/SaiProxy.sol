pragma solidity >=0.4.22 <0.6.0;

import "./DSMath.sol";
import "./SaiInterfaces.sol";

contract SaiProxy is DSMath {
    function open(address tub_) public returns (bytes32) {
        return TubInterface(tub_).open();
    }

    function give(address tub_, bytes32 cup, address lad) public {
        TubInterface(tub_).give(cup, lad);
    }

    function lock(address tub_, bytes32 cup) public payable {
        if (msg.value > 0) {
            TubInterface tub = TubInterface(tub_);

            (address lad,,,) = tub.cups(cup);
            require(lad == address(this), "cup-not-owned");

            tub.gem().deposit.value(msg.value)();

            uint ink = rdiv(msg.value, tub.per());
            ink = rmul(ink, tub.per()) <= msg.value ? ink : ink - 1;

            if (tub.gem().allowance(address(this), address(tub)) != uint(-1)) {
                tub.gem().approve(address(tub), uint(-1));
            }
            tub.join(ink);

            if (tub.skr().allowance(address(this), address(tub)) != uint(-1)) {
                tub.skr().approve(address(tub), uint(-1));
            }
            tub.lock(cup, ink);
        }
    }

    function draw(address tub_, bytes32 cup, uint wad) public {
        if (wad > 0) {
            TubInterface tub = TubInterface(tub_);
            tub.draw(cup, wad);
            tub.sai().transfer(msg.sender, wad);
        }
    }

    function handleGovFee(TubInterface tub, uint saiDebtFee, address otc_) internal {
        bytes32 val;
        bool ok;
        (val, ok) = tub.pep().peek();
        if (ok && val != 0) {
            uint govAmt = wdiv(saiDebtFee, uint(val));
            if (otc_ != address(0)) {
                uint saiGovAmt = OtcInterface(otc_).getPayAmount(address(tub.sai()), address(tub.gov()), govAmt);
                if (tub.sai().allowance(address(this), otc_) != uint(-1)) {
                    tub.sai().approve(otc_, uint(-1));
                }
                tub.sai().transferFrom(msg.sender, address(this), saiGovAmt);
                OtcInterface(otc_).buyAllAmount(address(tub.gov()), govAmt, address(tub.sai()), saiGovAmt);
            } else {
                tub.gov().transferFrom(msg.sender, address(this), govAmt);
            }
        }
    }

    function wipe(address tub_, bytes32 cup, uint wad, address otc_) public {
        if (wad > 0) {
            TubInterface tub = TubInterface(tub_);

            tub.sai().transferFrom(msg.sender, address(this), wad);
            handleGovFee(tub, rmul(wad, rdiv(tub.rap(cup), tub.tab(cup))), otc_);

            if (tub.sai().allowance(address(this), address(tub)) != uint(-1)) {
                tub.sai().approve(address(tub), uint(-1));
            }
            if (tub.gov().allowance(address(this), address(tub)) != uint(-1)) {
                tub.gov().approve(address(tub), uint(-1));
            }
            tub.wipe(cup, wad);
        }
    }

    function wipe(address tub_, bytes32 cup, uint wad) public {
        wipe(tub_, cup, wad, address(0));
    }

    function free(address tub_, bytes32 cup, uint jam) public {
        if (jam > 0) {
            TubInterface tub = TubInterface(tub_);
            uint ink = rdiv(jam, tub.per());
            ink = rmul(ink, tub.per()) <= jam ? ink : ink - 1;
            tub.free(cup, ink);
            if (tub.skr().allowance(address(this), address(tub)) != uint(-1)) {
                tub.skr().approve(address(tub), uint(-1));
            }
            tub.exit(ink);
            uint freeJam = tub.gem().balanceOf(address(this)); // Withdraw possible previous stuck WETH as well
            tub.gem().withdraw(freeJam);
            address(msg.sender).transfer(freeJam);
        }
    }

    function lockAndDraw(address tub_, bytes32 cup, uint wad) public payable {
        lock(tub_, cup);
        draw(tub_, cup, wad);
    }

    function openAndLockAndDraw(address tub_, uint wad) public payable returns (bytes32 cup) {
        cup = open(tub_);
        lockAndDraw(tub_, cup, wad);
    }

    function wipeAndFree(address tub_, bytes32 cup, uint jam, uint wad) public payable {
        wipe(tub_, cup, wad);
        free(tub_, cup, jam);
    }

    function wipeAndFree(address tub_, bytes32 cup, uint jam, uint wad, address otc_) public payable {
        wipe(tub_, cup, wad, otc_);
        free(tub_, cup, jam);
    }

    function shut(address tub_, bytes32 cup) public {
        TubInterface tub = TubInterface(tub_);
        wipeAndFree(tub_, cup, rmul(tub.ink(cup), tub.per()), tub.tab(cup));
        tub.shut(cup);
    }

    function shut(address tub_, bytes32 cup, address otc_) public {
        TubInterface tub = TubInterface(tub_);
        wipeAndFree(tub_, cup, rmul(tub.ink(cup), tub.per()), tub.tab(cup), otc_);
        tub.shut(cup);
    }
}