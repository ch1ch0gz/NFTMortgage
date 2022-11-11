async function main() {
  const Mortgage = await ethers.getContractFactory("Mortgage");
  mortgage = await Mortgage.deploy();
  await mortgage.deployed();

  console.log("My first mortgage deployed to:", mortgage.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
