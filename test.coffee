#u = require './util'
#h = require './halfnode'
#bt = require './block_template'
bignum = require 'bignum'
# console.log u.script_to_address '4Ph9EcSEVgPNR4Ezc1J4u1Kh1qD5uS9oyg'
# console.log u.script_to_address 'fo2iXqMQ6rqtjkZApPyKg2cNRAZh7efGYn'
# console.log u.b58decode('1Poaa5aA6STxxwAECayWosncCP9dFEF3tU').length
# console.log u.script_to_address '1Poaa5aA6STxxwAECayWosncCP9dFEF3tU'

#n = new bignum('000000000027e102000000000000000000000000000000000000000000000000', 16)
#d = new bignum('00000000ffff0000000000000000000000000000000000000000000000000000', 16)
time = new Date()
n = new bignum(2).pow(4194304)
console.log n.toString(), (+new Date() - time) / 1000

