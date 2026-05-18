package com.globalpayments.paymentsservice.repository;

import com.globalpayments.paymentsservice.model.entity.Payment;
import com.globalpayments.paymentsservice.model.enums.PaymentStatus;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Repository
public interface PaymentRepository extends JpaRepository<Payment, UUID> {

    Optional<Payment> findByPaymentReference(String paymentReference);

    Optional<Payment> findByIdempotencyKey(String idempotencyKey);

    Page<Payment> findBySenderAccountId(String senderAccountId, Pageable pageable);

    Page<Payment> findByReceiverAccountId(String receiverAccountId, Pageable pageable);

    Page<Payment> findByStatus(PaymentStatus status, Pageable pageable);

    /**
     * Find payments eligible for retry: FAILED status with retryCount below limit
     * and not updated in the last 5 minutes (to allow backoff).
     */
    @Query("""
        SELECT p FROM Payment p
        WHERE p.status = 'FAILED'
          AND p.retryCount < 3
          AND p.updatedAt < :cutoffTime
        ORDER BY p.createdAt ASC
    """)
    List<Payment> findRetryablePayments(@Param("cutoffTime") Instant cutoffTime);

    /**
     * Find PENDING payments older than 15 minutes — potential stale payments
     * that should be investigated.
     */
    @Query("""
        SELECT p FROM Payment p
        WHERE p.status = 'PENDING'
          AND p.createdAt < :cutoffTime
    """)
    List<Payment> findStalePendingPayments(@Param("cutoffTime") Instant cutoffTime);

    boolean existsByIdempotencyKey(String idempotencyKey);

    @Query("SELECT COUNT(p) FROM Payment p WHERE p.status = :status")
    long countByStatus(@Param("status") PaymentStatus status);
}
