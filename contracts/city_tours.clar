;; Constants and error codes
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-guide (err u103))
(define-constant err-already-booked (err u104))
(define-constant err-invalid-status (err u105))
(define-constant err-too-late (err u106))

;; Data structures 
(define-map tours
    { tour-id: uint }
    {
        guide: principal,
        title: (string-ascii 100),
        description: (string-utf8 500),
        price: uint,
        duration: uint,
        city: (string-ascii 50),
        available: bool,
        start-block: (optional uint)
    }
)

(define-map bookings
    { booking-id: uint }
    {
        tour-id: uint,
        traveler: principal,
        guide: principal,
        status: (string-ascii 20),
        payment-status: bool,
        review-submitted: bool,
        refund-status: (optional bool)
    }
)

(define-map guides
    { guide: principal }
    {
        verified: bool,
        rating: uint,
        total-reviews: uint,
        cancellations: uint
    }
)

;; Data variables
(define-data-var next-tour-id uint u1)
(define-data-var next-booking-id uint u1)
(define-data-var cancellation-deadline uint u150)

;; Guide management
(define-public (register-as-guide)
    (begin
        (map-set guides
            { guide: tx-sender }
            {
                verified: false,
                rating: u0,
                total-reviews: u0,
                cancellations: u0
            }
        )
        (ok true)
    )
)

(define-public (verify-guide (guide principal))
    (if (is-eq tx-sender contract-owner)
        (begin
            (map-set guides
                { guide: guide }
                (merge (unwrap! (map-get? guides {guide: guide}) err-not-found)
                    { verified: true })
            )
            (ok true)
        )
        err-owner-only
    )
)

;; Tour management
(define-public (create-tour (title (string-ascii 100)) (description (string-utf8 500)) 
                           (price uint) (duration uint) (city (string-ascii 50)) (start-block uint))
    (let ((guide-info (unwrap! (map-get? guides {guide: tx-sender}) err-invalid-guide)))
        (if (get verified guide-info)
            (let ((tour-id (var-get next-tour-id)))
                (map-set tours
                    { tour-id: tour-id }
                    {
                        guide: tx-sender,
                        title: title,
                        description: description,
                        price: price,
                        duration: duration,
                        city: city,
                        available: true,
                        start-block: (some start-block)
                    }
                )
                (var-set next-tour-id (+ tour-id u1))
                (ok tour-id)
            )
            err-unauthorized
        )
    )
)

;; Booking system
(define-public (book-tour (tour-id uint))
    (let (
        (tour (unwrap! (map-get? tours {tour-id: tour-id}) err-not-found))
        (booking-id (var-get next-booking-id))
    )
        (if (get available tour)
            (begin
                (try! (stx-transfer? (get price tour) tx-sender (get guide tour)))
                (map-set bookings
                    { booking-id: booking-id }
                    {
                        tour-id: tour-id,
                        traveler: tx-sender,
                        guide: (get guide tour),
                        status: "booked",
                        payment-status: true,
                        review-submitted: false,
                        refund-status: none
                    }
                )
                (map-set tours
                    { tour-id: tour-id }
                    (merge tour { available: false })
                )
                (var-set next-booking-id (+ booking-id u1))
                (ok booking-id)
            )
            err-already-booked
        )
    )
)

;; Cancellation and refund system
(define-public (cancel-tour (booking-id uint))
    (let (
        (booking (unwrap! (map-get? bookings {booking-id: booking-id}) err-not-found))
        (tour (unwrap! (map-get? tours {tour-id: (get tour-id booking)}) err-not-found))
        (guide-info (unwrap! (map-get? guides {guide: (get guide booking)}) err-not-found))
        (start-block (unwrap! (get start-block tour) err-not-found))
    )
        (asserts! (or (is-eq tx-sender (get guide booking)) 
                     (is-eq tx-sender (get traveler booking))) 
                 err-unauthorized)
        (asserts! (is-eq (get status booking) "booked") err-invalid-status)
        (asserts! (> start-block block-height) err-too-late)
        
        (if (is-eq tx-sender (get guide booking))
            (begin
                ;; Guide cancellation - full refund + update guide metrics
                (try! (stx-transfer? (get price tour) (get guide booking) (get traveler booking)))
                (map-set guides 
                    {guide: (get guide booking)}
                    (merge guide-info 
                        {cancellations: (+ (get cancellations guide-info) u1)})
                )
                (map-set bookings
                    {booking-id: booking-id}
                    (merge booking 
                        {
                            status: "cancelled-by-guide",
                            refund-status: (some true)
                        })
                )
                (map-set tours
                    {tour-id: (get tour-id booking)}
                    (merge tour {available: true})
                )
                (ok true)
            )
            (if (>= (- start-block block-height) (var-get cancellation-deadline))
                (begin
                    ;; Early traveler cancellation - full refund
                    (try! (stx-transfer? (get price tour) (get guide booking) (get traveler booking)))
                    (map-set bookings
                        {booking-id: booking-id}
                        (merge booking 
                            {
                                status: "cancelled-by-traveler",
                                refund-status: (some true)
                            })
                    )
                    (map-set tours
                        {tour-id: (get tour-id booking)}
                        (merge tour {available: true})
                    )
                    (ok true)
                )
                ;; Late traveler cancellation - no refund
                (begin
                    (map-set bookings
                        {booking-id: booking-id}
                        (merge booking 
                            {
                                status: "cancelled-by-traveler",
                                refund-status: (some false)
                            })
                    )
                    (ok true)
                )
            )
        )
    )
)

;; Review system
(define-public (submit-review (booking-id uint) (rating uint))
    (let (
        (booking (unwrap! (map-get? bookings {booking-id: booking-id}) err-not-found))
        (guide-info (unwrap! (map-get? guides {guide: (get guide booking)}) err-not-found))
    )
        (if (and
            (is-eq tx-sender (get traveler booking))
            (not (get review-submitted booking))
        )
            (begin
                (map-set guides
                    { guide: (get guide booking) }
                    {
                        verified: (get verified guide-info),
                        rating: (/ (+ (* (get rating guide-info) (get total-reviews guide-info)) rating)
                                 (+ (get total-reviews guide-info) u1)),
                        total-reviews: (+ (get total-reviews guide-info) u1),
                        cancellations: (get cancellations guide-info)
                    }
                )
                (map-set bookings
                    { booking-id: booking-id }
                    (merge booking { review-submitted: true })
                )
                (ok true)
            )
            err-unauthorized
        )
    )
)

;; Read-only functions
(define-read-only (get-tour-details (tour-id uint))
    (map-get? tours { tour-id: tour-id })
)

(define-read-only (get-guide-info (guide principal))
    (map-get? guides { guide: guide })
)

(define-read-only (get-booking-details (booking-id uint))
    (map-get? bookings { booking-id: booking-id })
)

(define-read-only (get-cancellation-deadline)
    (var-get cancellation-deadline)
)
