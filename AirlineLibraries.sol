// SPDX-License-Identifier: MIT
// Author: Ashhar (RGV2)

pragma solidity >=0.8.0 <0.9.0;

library AirlineLibraries {
    struct _Date {
        uint16 year;
        uint8 month;
        uint8 day;
    }

    uint constant DAY_IN_SECONDS = 86400;
    uint constant YEAR_IN_SECONDS = 31536000;
    uint constant LEAP_YEAR_IN_SECONDS = 31622400;
    uint16 constant ORIGIN_YEAR = 1970;

    function isLeapYear(uint16 year) private pure returns (bool) {
        if (year % 4 != 0) {
            return false;
        }
        if (year % 100 != 0) {
            return true;
        }
        if (year % 400 != 0) {
            return false;
        }
        return true;
    }

    function leapYearsBefore(uint year) private pure returns (uint) {
        year -= 1;
        return year / 4 - year / 100 + year / 400;
    }

    function getDaysInMonth(uint8 month, uint16 year) private pure returns (uint8) {
        if (month == 1 || month == 3 || month == 5 || month == 7 || month == 8 || month == 10 || month == 12) {
            return 31;
        }
        else if (month == 4 || month == 6 || month == 9 || month == 11) {
            return 30;
        }
        else if (isLeapYear(year)) {
            return 29;
        }
        else {
            return 28;
        }
    }

    // EPOCH to Date Conversion in String format
    function parseTimestamp(uint timestamp) public pure returns (string memory date) {
        _Date memory _date;
        
        uint secondsAccountedFor = 0;
        uint buf;
        uint8 i;

        // Year
        _date.year = getYear(timestamp);
        buf = leapYearsBefore(_date.year) - leapYearsBefore(ORIGIN_YEAR);

        secondsAccountedFor += LEAP_YEAR_IN_SECONDS * buf;
        secondsAccountedFor += YEAR_IN_SECONDS * (_date.year - ORIGIN_YEAR - buf);

        // Month
        uint secondsInMonth;
        for (i = 1; i <= 12; i++) {
                secondsInMonth = DAY_IN_SECONDS * getDaysInMonth(i, _date.year);
                if (secondsInMonth + secondsAccountedFor > timestamp) {
                        _date.month = i;
                        break;
                }
                secondsAccountedFor += secondsInMonth;
        }

        // Day
        for (i = 1; i <= getDaysInMonth(_date.month, _date.year); i++) {
                if (DAY_IN_SECONDS + secondsAccountedFor > timestamp) {
                        _date.day = i;
                        break;
                }
                secondsAccountedFor += DAY_IN_SECONDS;
        }
        date = string(abi.encodePacked(toString(_date.day), "-", toString(_date.month), "-", toString(_date.year)));
    }

    function getYear(uint timestamp) private pure returns (uint16) {
        uint secondsAccountedFor = 0;
        uint16 year;
        uint numLeapYears;

        // Year
        year = uint16(ORIGIN_YEAR + timestamp / YEAR_IN_SECONDS);
        numLeapYears = leapYearsBefore(year) - leapYearsBefore(ORIGIN_YEAR);

        secondsAccountedFor += LEAP_YEAR_IN_SECONDS * numLeapYears;
        secondsAccountedFor += YEAR_IN_SECONDS * (year - ORIGIN_YEAR - numLeapYears);

        while (secondsAccountedFor > timestamp) {
                if (isLeapYear(uint16(year - 1))) {
                        secondsAccountedFor -= LEAP_YEAR_IN_SECONDS;
                }
                else {
                        secondsAccountedFor -= YEAR_IN_SECONDS;
                }
                year -= 1;
        }
        return year;
    }
    
    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
    
    // Function to compare two strings.
    function compareStrings(string memory value1, string memory value2) public pure returns (bool) {
        return (keccak256(abi.encodePacked(value1)) == keccak256(abi.encodePacked(value2)));
    }
}
