const TESTDOGE = artifacts.require("TESTDOGE");

const { router } = require('../secrets.json');

module.exports = async function (deployer) {
  await deployer.deploy(TESTDOGE, router);
};
