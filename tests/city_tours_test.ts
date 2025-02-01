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

        const startBlock = chain.blockHeight + 200;

        // Create tour
        let tourBlock = chain.mineBlock([
            Tx.contractCall('city_tours', 'create-tour', [
                types.ascii("Paris Walking Tour"),
                types.utf8("Explore the heart of Paris"),
                types.uint(100),
                types.uint(180),
                types.ascii("Paris"),
                types.uint(startBlock)
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
    name: "Early cancellation and refund flow",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const guide = accounts.get('wallet_1')!;
        const traveler = accounts.get('wallet_2')!;

        // Setup complete tour booking
        let setup = chain.mineBlock([
            Tx.contractCall('city_tours', 'register-as-guide', [], guide.address),
            Tx.contractCall('city_tours', 'verify-guide', [types.principal(guide.address)], deployer.address)
        ]);

        const startBlock = chain.blockHeight + 200;

        let tour = chain.mineBlock([
            Tx.contractCall('city_tours', 'create-tour', [
                types.ascii("Paris Walking Tour"),
                types.utf8("Explore the heart of Paris"),
                types.uint(100),
                types.uint(180),
                types.ascii("Paris"),
                types.uint(startBlock)
            ], guide.address)
        ]);

        let tourId = tour.receipts[0].result.expectOk();
        
        let booking = chain.mineBlock([
            Tx.contractCall('city_tours', 'book-tour', [tourId], traveler.address)
        ]);

        let bookingId = booking.receipts[0].result.expectOk();

        // Cancel tour early (should get full refund)
        let cancelBlock = chain.mineBlock([
            Tx.contractCall('city_tours', 'cancel-tour', [
                bookingId
            ], traveler.address)
        ]);

        cancelBlock.receipts[0].result.expectOk();

        // Verify booking status and refund
        let bookingInfo = chain.callReadOnlyFn(
            'city_tours',
            'get-booking-details',
            [bookingId],
            deployer.address
        );
        
        let updatedBooking = bookingInfo.result.expectSome();
        assertEquals(updatedBooking['status'], "cancelled-by-traveler");
        assertEquals(updatedBooking['refund-status'].value, true);
    }
});

Clarinet.test({
    name: "Guide cancellation flow",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const guide = accounts.get('wallet_1')!;
        const traveler = accounts.get('wallet_2')!;

        // Setup
        let setup = chain.mineBlock([
            Tx.contractCall('city_tours', 'register-as-guide', [], guide.address),
            Tx.contractCall('city_tours', 'verify-guide', [types.principal(guide.address)], deployer.address)
        ]);

        const startBlock = chain.blockHeight + 200;

        let tour = chain.mineBlock([
            Tx.contractCall('city_tours', 'create-tour', [
                types.ascii("Paris Walking Tour"),
                types.utf8("Explore the heart of Paris"),
                types.uint(100),
                types.uint(180),
                types.ascii("Paris"),
                types.uint(startBlock)
            ], guide.address)
        ]);

        let tourId = tour.receipts[0].result.expectOk();
        
        let booking = chain.mineBlock([
            Tx.contractCall('city_tours', 'book-tour', [tourId], traveler.address)
        ]);

        let bookingId = booking.receipts[0].result.expectOk();

        // Guide cancels tour
        let cancelBlock = chain.mineBlock([
            Tx.contractCall('city_tours', 'cancel-tour', [
                bookingId
            ], guide.address)
        ]);

        cancelBlock.receipts[0].result.expectOk();

        // Verify guide cancellation count increased
        let guideInfo = chain.callReadOnlyFn(
            'city_tours',
            'get-guide-info',
            [types.principal(guide.address)],
            deployer.address
        );
        
        let info = guideInfo.result.expectSome();
        assertEquals(info['cancellations'], types.uint(1));
    }
});
