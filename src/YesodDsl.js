// module YesodDsl

// from https://github.com/slamdata/purescript-jtable/blob/master/src/Data/Json/JSemantic.js

exports.s2nImpl = function(Just) {
    return function(Nothing) {
        return function(s) {
            var n = s * 1;
            if (isNaN(n)) {
                return Nothing;
            }
            else {
                return Just(n);
            }
        };
    };
};

exports.toString = function(d) {
    return d.toString();
};

exports.jsDateToISOString = function(d) {
    return d.toISOString();
};
