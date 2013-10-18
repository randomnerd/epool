(function() {
  require('coffee-script')
  var Pool, config, config_path, pool;

  config_path = process.argv[2] || './config';
  config = require(config_path);

  Pool = require('./pool');
  pool = new Pool(config);

  pool.start();

  // run garbage collector every 3 minutes if available
  if (typeof(gc) === "function") { setInterval(gc, 180*1000); }

}).call(this);
