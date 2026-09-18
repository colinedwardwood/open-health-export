A timed-out accessibility audit is not retried inside the same test. Hosted
iPhone 2 spent three minutes in RTL empty (-56) and then lost the simulator
for the rest of the shard; workflow retry relaunches instead.
