;; Constants and error codes
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))        ;; Only contract owner can perform this action
(define-constant err-not-found (err u101))         ;; Requested resource not found
(define-constant err-unauthorized (err u102))      ;; User not authorized for this action
(define-constant err-invalid-guide (err u103))     ;; Guide not registered or invalid
(define-constant err-already-booked (err u104))    ;; Tour is already booked
(define-constant err-invalid-status (err u105))    ;; Invalid booking status
(define-constant err-too-late (err u106))         ;; Past cancellation deadline
(define-constant err-invalid-rating (err u107))    ;; Rating must be between 1 and 5

;; Data structures 
[previous data structures remain unchanged...]

;; Review system
(define-public (submit-review (booking-id uint) (rating uint))
    (let (
        (booking (unwrap! (map-get? bookings {booking-id: booking-id}) err-not-found))
        (guide-info (unwrap! (map-get? guides {guide: (get guide booking)}) err-not-found))
    )
        (asserts! (and (>= rating u1) (<= rating u5)) err-invalid-rating)
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

[rest of the contract remains unchanged...]
