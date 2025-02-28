[previous test content...]

Clarinet.test({
    name: "Review system validation",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const guide = accounts.get('wallet_1')!;
        const traveler = accounts.get('wallet_2')!;

        // Setup complete booking
        let setup = chain.mineBlock([
            Tx.contractCall('city_tours', 'register-as-guide', [], guide.address),
            Tx.contractCall('city_tours', 'verify-guide', [types.principal(guide.address)], deployer.address)
        ]);

        const startBlock = chain.blockHeight + 200;
        
        let tour = chain.mineBlock([
            Tx.contractCall('city_tours', 'create-tour', [
                types.ascii("Test Tour"),
                types.utf8("Description"),
                types.uint(100),
                types.uint(180),
                types.ascii("City"),
                types.uint(startBlock)
            ], guide.address)
        ]);

        let tourId = tour.receipts[0].result.expectOk();
        
        let booking = chain.mineBlock([
            Tx.contractCall('city_tours', 'book-tour', [tourId], traveler.address)
        ]);

        let bookingId = booking.receipts[0].result.expectOk();

        // Test invalid rating
        let invalidReview = chain.mineBlock([
            Tx.contractCall('city_tours', 'submit-review', [
                bookingId,
                types.uint(6)
            ], traveler.address)
        ]);

        invalidReview.receipts[0].result.expectErr(107); // err-invalid-rating

        // Test valid rating
        let validReview = chain.mineBlock([
            Tx.contractCall('city_tours', 'submit-review', [
                bookingId,
                types.uint(5)
            ], traveler.address)
        ]);

        validReview.receipts[0].result.expectOk();
    }
});
