;; ai-registry.clar
;; Core contract for AI model registration and management

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_INVALID_MODEL (err u101))
(define-constant ERR_MODEL_EXISTS (err u102))
(define-constant ERR_MODEL_NOT_FOUND (err u103))
(define-constant ERR_INVALID_STATUS (err u104))

;; Data Maps
(define-map ai-models
    {model-id: uint}
    {
        owner: principal,
        name: (string-ascii 50),
        description: (string-utf8 500),
        version: uint,
        status: (string-ascii 20),  ;; "pending", "auditing", "certified", "rejected"
        training-data-hash: (buff 32),
        creation-time: uint,
        last-updated: uint
    }
)

(define-map model-metrics
    {model-id: uint}
    {
        total-audits: uint,
        current-score: uint,
        bias-reports: uint,
        last-audit-date: uint
    }
)

;; Data Variables
(define-data-var last-model-id uint u0)
(define-data-var total-models uint u0)
(define-data-var platform-status (string-ascii 20) "active")

;; Private Functions
(define-private (is-contract-owner)
    (is-eq tx-sender CONTRACT_OWNER)
)

(define-private (validate-status (status (string-ascii 20)))
    (or 
        (is-eq status "pending")
        (is-eq status "auditing")
        (is-eq status "certified")
        (is-eq status "rejected")
    )
)

(define-private (increment-model-id)
    (begin
        (var-set last-model-id (+ (var-get last-model-id) u1))
        (var-get last-model-id)
    )
)

;; Public Functions

;; Register a new AI model
(define-public (register-model
        (name (string-ascii 50))
        (description (string-utf8 500))
        (training-data-hash (buff 32)))
    (let 
        (
            (new-model-id (increment-model-id))
            (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
        )
        (asserts! (is-eq (len training-data-hash) u32) ERR_INVALID_MODEL)
        (map-insert ai-models
            {model-id: new-model-id}
            {
                owner: tx-sender,
                name: name,
                description: description,
                version: u1,
                status: "pending",
                training-data-hash: training-data-hash,
                creation-time: current-time,
                last-updated: current-time
            }
        )
        (map-insert model-metrics
            {model-id: new-model-id}
            {
                total-audits: u0,
                current-score: u0,
                bias-reports: u0,
                last-audit-date: u0
            }
        )
        (var-set total-models (+ (var-get total-models) u1))
        (ok new-model-id)
    )
)

;; Update model metadata
(define-public (update-model
        (model-id uint)
        (new-description (string-utf8 500))
        (new-training-data-hash (buff 32)))
    (let 
        ((model-data (unwrap! (map-get? ai-models {model-id: model-id}) ERR_MODEL_NOT_FOUND))
         (current-time (unwrap-panic (get-block-info? time (- block-height u1)))))
        (asserts! (is-eq (get owner model-data) tx-sender) ERR_NOT_AUTHORIZED)
        (asserts! (is-eq (len new-training-data-hash) u32) ERR_INVALID_MODEL)
        (ok (map-set ai-models
            {model-id: model-id}
            (merge model-data
                {
                    description: new-description,
                    training-data-hash: new-training-data-hash,
                    version: (+ (get version model-data) u1),
                    last-updated: current-time
                }
            )))
    )
)

;; Update model status (restricted to contract owner)
(define-public (update-model-status
        (model-id uint)
        (new-status (string-ascii 20)))
    (let ((model-data (unwrap! (map-get? ai-models {model-id: model-id}) ERR_MODEL_NOT_FOUND)))
        (asserts! (is-contract-owner) ERR_NOT_AUTHORIZED)
        (asserts! (validate-status new-status) ERR_INVALID_STATUS)
        (ok (map-set ai-models
            {model-id: model-id}
            (merge model-data {status: new-status})))
    )
)

;; Report bias for a model
(define-public (report-bias (model-id uint))
    (let ((metrics (unwrap! (map-get? model-metrics {model-id: model-id}) ERR_MODEL_NOT_FOUND)))
        (ok (map-set model-metrics
            {model-id: model-id}
            (merge metrics {bias-reports: (+ (get bias-reports metrics) u1)})))
    )
)

;; Getter Functions

;; Get model details
(define-read-only (get-model-details (model-id uint))
    (map-get? ai-models {model-id: model-id})
)

;; Get model metrics
(define-read-only (get-model-metrics (model-id uint))
    (map-get? model-metrics {model-id: model-id})
)

;; Get total number of registered models
(define-read-only (get-total-models)
    (var-get total-models)
)

;; Get platform status
(define-read-only (get-platform-status)
    (var-get platform-status)
)

;; Emergency Functions

;; Pause platform (owner only)
(define-public (pause-platform)
    (begin
        (asserts! (is-contract-owner) ERR_NOT_AUTHORIZED)
        (var-set platform-status "paused")
        (ok true)
    )
)

;; Resume platform (owner only)
(define-public (resume-platform)
    (begin
        (asserts! (is-contract-owner) ERR_NOT_AUTHORIZED)
        (var-set platform-status "active")
        (ok true)
    )
)