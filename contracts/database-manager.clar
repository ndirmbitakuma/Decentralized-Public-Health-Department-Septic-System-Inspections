;; Database Manager Contract
;; Tracks septic system locations and inspection history

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-SYSTEM-NOT-FOUND (err u501))
(define-constant ERR-SYSTEM-EXISTS (err u502))
(define-constant ERR-INVALID-INPUT (err u503))
(define-constant ERR-INVALID-COORDINATES (err u504))

;; Data Variables
(define-data-var next-system-id uint u1)
(define-data-var total-systems uint u0)

;; Data Maps
(define-map septic-systems
  { system-id: uint }
  {
    owner: principal,
    property-address: (string-ascii 200),
    latitude: int,
    longitude: int,
    system-type: (string-ascii 50),
    capacity: uint,
    installation-date: uint,
    last-inspection: (optional uint),
    next-inspection-due: (optional uint),
    status: (string-ascii 20),
    permit-id: (optional uint)
  }
)

(define-map owner-systems
  { owner: principal }
  {
    system-count: uint,
    system-ids: (list 10 uint)
  }
)

(define-map location-systems
  { latitude: int, longitude: int }
  {
    system-id: uint,
    property-address: (string-ascii 200)
  }
)

(define-map system-history
  { system-id: uint }
  {
    creation-date: uint,
    last-updated: uint,
    update-count: uint,
    status-history: (list 20 (string-ascii 20))
  }
)

;; Public Functions

;; Register new septic system
(define-public (register-system
  (property-address (string-ascii 200))
  (latitude int)
  (longitude int)
  (system-type (string-ascii 50))
  (capacity uint)
  (installation-date uint)
  (permit-id (optional uint)))
  (let
    (
      (system-id (var-get next-system-id))
      (current-block-height block-height)
    )
    (asserts! (> (len property-address) u0) ERR-INVALID-INPUT)
    (asserts! (and (>= latitude -90000000) (<= latitude 90000000)) ERR-INVALID-COORDINATES)
    (asserts! (and (>= longitude -180000000) (<= longitude 180000000)) ERR-INVALID-COORDINATES)
    (asserts! (> (len system-type) u0) ERR-INVALID-INPUT)
    (asserts! (> capacity u0) ERR-INVALID-INPUT)
    (asserts! (> installation-date u0) ERR-INVALID-INPUT)

    ;; Check if location already has a system
    (asserts! (is-none (map-get? location-systems { latitude: latitude, longitude: longitude })) ERR-SYSTEM-EXISTS)

    (map-set septic-systems
      { system-id: system-id }
      {
        owner: tx-sender,
        property-address: property-address,
        latitude: latitude,
        longitude: longitude,
        system-type: system-type,
        capacity: capacity,
        installation-date: installation-date,
        last-inspection: none,
        next-inspection-due: none,
        status: "active",
        permit-id: permit-id
      }
    )

    ;; Update location mapping
    (map-set location-systems
      { latitude: latitude, longitude: longitude }
      {
        system-id: system-id,
        property-address: property-address
      }
    )

    ;; Update owner systems
    (update-owner-systems tx-sender system-id)

    ;; Initialize system history
    (map-set system-history
      { system-id: system-id }
      {
        creation-date: current-block-height,
        last-updated: current-block-height,
        update-count: u1,
        status-history: (list "active")
      }
    )

    (var-set next-system-id (+ system-id u1))
    (var-set total-systems (+ (var-get total-systems) u1))
    (ok system-id)
  )
)

;; Update system status
(define-public (update-system-status (system-id uint) (new-status (string-ascii 20)))
  (let
    (
      (system (unwrap! (map-get? septic-systems { system-id: system-id }) ERR-SYSTEM-NOT-FOUND))
      (history (unwrap! (map-get? system-history { system-id: system-id }) ERR-SYSTEM-NOT-FOUND))
      (current-block-height block-height)
    )
    (asserts! (is-eq (get owner system) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> (len new-status) u0) ERR-INVALID-INPUT)

    (map-set septic-systems
      { system-id: system-id }
      (merge system { status: new-status })
    )

    ;; Update system history
    (map-set system-history
      { system-id: system-id }
      (merge history {
        last-updated: current-block-height,
        update-count: (+ (get update-count history) u1),
        status-history: (unwrap-panic (as-max-len?
                                       (append (get status-history history) new-status)
                                       u20))
      })
    )

    (ok true)
  )
)

;; Update inspection dates
(define-public (update-inspection-dates (system-id uint) (last-inspection uint) (next-due uint))
  (let
    (
      (system (unwrap! (map-get? septic-systems { system-id: system-id }) ERR-SYSTEM-NOT-FOUND))
    )
    (asserts! (> last-inspection u0) ERR-INVALID-INPUT)
    (asserts! (> next-due last-inspection) ERR-INVALID-INPUT)

    (map-set septic-systems
      { system-id: system-id }
      (merge system {
        last-inspection: (some last-inspection),
        next-inspection-due: (some next-due)
      })
    )
    (ok true)
  )
)

;; Transfer system ownership
(define-public (transfer-ownership (system-id uint) (new-owner principal))
  (let
    (
      (system (unwrap! (map-get? septic-systems { system-id: system-id }) ERR-SYSTEM-NOT-FOUND))
    )
    (asserts! (is-eq (get owner system) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-eq tx-sender new-owner)) ERR-INVALID-INPUT)

    (map-set septic-systems
      { system-id: system-id }
      (merge system { owner: new-owner })
    )

    ;; Update owner mappings
    (remove-from-owner-systems tx-sender system-id)
    (update-owner-systems new-owner system-id)

    (ok true)
  )
)

;; Read-Only Functions

;; Get system details
(define-read-only (get-system (system-id uint))
  (map-get? septic-systems { system-id: system-id })
)

;; Get systems by owner
(define-read-only (get-owner-systems (owner principal))
  (map-get? owner-systems { owner: owner })
)

;; Get system at location
(define-read-only (get-system-at-location (latitude int) (longitude int))
  (map-get? location-systems { latitude: latitude, longitude: longitude })
)

;; Get system history
(define-read-only (get-system-history (system-id uint))
  (map-get? system-history { system-id: system-id })
)

;; Get total systems count
(define-read-only (get-total-systems)
  (var-get total-systems)
)

;; Check if system needs inspection
(define-read-only (needs-inspection (system-id uint))
  (match (map-get? septic-systems { system-id: system-id })
    system (match (get next-inspection-due system)
             due-date (< due-date block-height)
             true) ;; No inspection scheduled yet
    false
  )
)

;; Get systems needing inspection in area
(define-read-only (get-systems-in-radius (center-lat int) (center-lon int) (radius int))
  ;; Simplified radius check - in production would use proper geospatial calculations
  (let
    (
      (lat-min (- center-lat radius))
      (lat-max (+ center-lat radius))
      (lon-min (- center-lon radius))
      (lon-max (+ center-lon radius))
    )
    ;; This is a simplified implementation
    ;; In production, would iterate through systems and check distance
    (ok true)
  )
)

;; Private Functions

;; Update owner systems mapping
(define-private (update-owner-systems (owner principal) (system-id uint))
  (let
    (
      (current-info (default-to
                      { system-count: u0, system-ids: (list) }
                      (map-get? owner-systems { owner: owner })))
    )
    (map-set owner-systems
      { owner: owner }
      {
        system-count: (+ (get system-count current-info) u1),
        system-ids: (unwrap-panic (as-max-len?
                                   (append (get system-ids current-info) system-id)
                                   u10))
      }
    )
  )
)

;; Remove system from owner mapping
(define-private (remove-from-owner-systems (owner principal) (system-id uint))
  (let
    (
      (current-info (unwrap-panic (map-get? owner-systems { owner: owner })))
    )
    (map-set owner-systems
      { owner: owner }
      {
        system-count: (- (get system-count current-info) u1),
        system-ids: (filter-system-id (get system-ids current-info) system-id)
      }
    )
  )
)

;; Filter out specific system ID from list
(define-private (filter-system-id (system-list (list 10 uint)) (target-id uint))
  (fold filter-system-id-fold system-list (list))
)

;; Fold function to filter system IDs
(define-private (filter-system-id-fold (system-id uint) (acc (list 10 uint)))
  (if (is-eq system-id (var-get next-system-id)) ;; placeholder logic
    acc
    (unwrap-panic (as-max-len? (append acc system-id) u10))
  )
)

;; Data Maps
(define-map licensed-contractors
  { contractor: principal }
  {
    active: bool,
    license-expiry: uint
  }
)

;; Read-Only Functions

;; Check if contractor is licensed
(define-read-only (is-contractor-licensed (contractor principal))
  (match (map-get? licensed-contractors { contractor: contractor })
    contractor-info (and
                      (get active contractor-info)
                      (> (get license-expiry contractor-info) block-height))
    false
  )
)
