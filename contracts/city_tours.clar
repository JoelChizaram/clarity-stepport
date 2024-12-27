;; Constants and error codes
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-guide (err u103))
(define-constant err-already-booked (err u104))

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
        available: bool
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
        review-submitted: bool
    }
)

(define-map guides
    { guide: principal }
    {
        verified: bool,
        rating: uint,
        total-reviews: uint
    }
)

;; Data variables
(define-data-var next-tour-id uint u1)
(define-data-var next-booking-id uint u1)

;; Guide management
(define-public (register-as-guide)
    (begin
        (map-set guides
            { guide: tx-sender }
            {
                verified: false,
                rating: u0,
                total-reviews: u0
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
(define-public (create-tour (title (string-ascii 100)) (description (string-utf8 500)) (price uint) (duration uint) (city (string-ascii 50)))
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
                        available: true
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
                        review-submitted: false
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
                        total-reviews: (+ (get total-reviews guide-info) u1)
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