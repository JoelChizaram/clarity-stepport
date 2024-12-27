import {
  Clarinet,
  Tx,
  Chain,
  Account,
  types
} from 'https://deno.land/x/clarinet@v1.0.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.90.0/testing/asserts.ts';

Clarinet.test({
    name: "Guide registration and verification flow",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const guide = accounts.get('wallet_1')!;

        let block = chain.mineBlock([
            Tx.contractCall('city_tours', 'register-as-guide', [], guide.address),
            Tx.contractCall('city_tours', 'verify-guide', [types.principal(guide.address)], deployer.address)
        ]);

        block.receipts[0].result.expectOk();
        block.receipts[1].result.expectOk();

        // Verify guide info
        let guideInfo = chain.callReadOnlyFn('city_tours', 'get-guide-info', [types.principal(guide.address)], deployer.address);
        assertEquals(guideInfo.result.expectSome().verified, true);
    }
});

Clarinet.test({
    name: "Tour creation and booking flow",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const guide = accounts.get('wallet_1')!;
        const traveler = accounts.get('wallet_2')!;

        // Setup: Register and verify guide
        let setup = chain.mineBlock([
            Tx.contractCall('city_tours', 'register-as-guide', [], guide.address),
            Tx.contractCall('city_tours', 'verify-guide', [types.principal(guide.address)], deployer.address)
        ]);

        // Create tour
        let tourBlock = chain.mineBlock([
            Tx.contractCall('city_tours', 'create-tour', [
                types.ascii("Paris Walking Tour"),
                types.utf8("Explore the heart of Paris"),
                types.uint(100),
                types.uint(180),
                types.ascii("Paris")
            ], guide.address)
        ]);

        let tourId = tourBlock.receipts[0].result.expectOk();

        // Book tour
        let bookingBlock = chain.mineBlock([
            Tx.contractCall('city_tours', 'book-tour', [tourId], traveler.address)
        ]);

        bookingBlock.receipts[0].result.expectOk();

        // Verify booking details
        let bookingId = bookingBlock.receipts[0].result.expectOk();
        let bookingInfo = chain.callReadOnlyFn(
            'city_tours',
            'get-booking-details',
            [bookingId],
            deployer.address
        );

        let booking = bookingInfo.result.expectSome();
        assertEquals(booking['traveler'], traveler.address);
        assertEquals(booking['payment-status'], true);
    }
});

Clarinet.test({
    name: "Review submission flow",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const guide = accounts.get('wallet_1')!;
        const traveler = accounts.get('wallet_2')!;

        // Setup complete tour booking
        let setup = chain.mineBlock([
            Tx.contractCall('city_tours', 'register-as-guide', [], guide.address),
            Tx.contractCall('city_tours', 'verify-guide', [types.principal(guide.address)], deployer.address),
            Tx.contractCall('city_tours', 'create-tour', [
                types.ascii("Paris Walking Tour"),
                types.utf8("Explore the heart of Paris"),
                types.uint(100),
                types.uint(180),
                types.ascii("Paris")
            ], guide.address)
        ]);

        let tourId = setup.receipts[2].result.expectOk();
        
        let booking = chain.mineBlock([
            Tx.contractCall('city_tours', 'book-tour', [tourId], traveler.address)
        ]);

        let bookingId = booking.receipts[0].result.expectOk();

        // Submit review
        let reviewBlock = chain.mineBlock([
            Tx.contractCall('city_tours', 'submit-review', [
                bookingId,
                types.uint(5)
            ], traveler.address)
        ]);

        reviewBlock.receipts[0].result.expectOk();

        // Verify guide rating updated
        let guideInfo = chain.callReadOnlyFn(
            'city_tours',
            'get-guide-info',
            [types.principal(guide.address)],
            deployer.address
        );
        
        let info = guideInfo.result.expectSome();
        assertEquals(info['rating'], types.uint(5));
        assertEquals(info['total-reviews'], types.uint(1));
    }
});