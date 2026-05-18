package com.globalpayments.paymentsservice.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.globalpayments.paymentsservice.exception.GlobalExceptionHandler;
import com.globalpayments.paymentsservice.exception.PaymentNotFoundException;
import com.globalpayments.paymentsservice.model.dto.PaymentDtos.*;
import com.globalpayments.paymentsservice.model.enums.Currency;
import com.globalpayments.paymentsservice.model.enums.PaymentStatus;
import com.globalpayments.paymentsservice.model.enums.PaymentType;
import com.globalpayments.paymentsservice.service.PaymentService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.MediaType;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Unit tests for PaymentController.
 *
 * Uses MockMvc with MockitoExtension — no Spring context loaded,
 * so tests run in milliseconds. The service layer is mocked.
 *
 * Integration tests (Testcontainers + real DB) live in
 * PaymentServiceIntegrationTest.java.
 */
@ExtendWith(MockitoExtension.class)
class PaymentControllerTest {

    @Mock
    private PaymentService paymentService;

    @InjectMocks
    private PaymentController paymentController;

    private MockMvc mockMvc;
    private ObjectMapper objectMapper;

    private static final UUID PAYMENT_ID   = UUID.randomUUID();
    private static final String PAYMENT_REF = "PAY-20240315-000001-AB12";

    @BeforeEach
    void setUp() {
        objectMapper = new ObjectMapper().findAndRegisterModules();
        mockMvc = MockMvcBuilders
            .standaloneSetup(paymentController)
            .setControllerAdvice(new GlobalExceptionHandler())
            .build();
    }

    // ── Helper builders ────────────────────────────────────────────────────

    private PaymentResponse buildMockResponse() {
        return PaymentResponse.builder()
            .id(PAYMENT_ID)
            .paymentReference(PAYMENT_REF)
            .senderAccountId("GB29NWBK60161331926819")
            .receiverAccountId("GB82WEST12345698765432")
            .receiverBankCode("BARCGB22")
            .amount(new BigDecimal("250.00"))
            .currency(Currency.GBP)
            .status(PaymentStatus.PENDING)
            .paymentType(PaymentType.DOMESTIC)
            .description("Test payment")
            .retryCount(0)
            .createdAt(Instant.now())
            .updatedAt(Instant.now())
            .createdBy("test-user")
            .build();
    }

    private String buildValidRequestJson() throws Exception {
        return objectMapper.writeValueAsString(
            CreatePaymentRequest.builder()
                .senderAccountId("GB29NWBK60161331926819")
                .receiverAccountId("GB82WEST12345698765432")
                .receiverBankCode("BARCGB22")
                .amount(new BigDecimal("250.00"))
                .currency(Currency.GBP)
                .paymentType(PaymentType.DOMESTIC)
                .description("Unit test payment")
                .build()
        );
    }

    // ── POST /api/v1/payments ──────────────────────────────────────────────

    @Nested
    @DisplayName("POST /api/v1/payments")
    class CreatePayment {

        @Test
        @DisplayName("should return 201 with created payment")
        @WithMockUser(roles = "PAYMENT_INITIATOR")
        void shouldReturn201WhenValidRequest() throws Exception {
            when(paymentService.createPayment(any())).thenReturn(buildMockResponse());

            mockMvc.perform(post("/api/v1/payments")
                    .contentType(MediaType.APPLICATION_JSON)
                    .content(buildValidRequestJson()))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.paymentReference").value(PAYMENT_REF))
                .andExpect(jsonPath("$.status").value("PENDING"))
                .andExpect(jsonPath("$.currency").value("GBP"));

            verify(paymentService, times(1)).createPayment(any());
        }

        @Test
        @DisplayName("should return 400 when amount is negative")
        @WithMockUser(roles = "PAYMENT_INITIATOR")
        void shouldReturn400WhenAmountNegative() throws Exception {
            String badRequest = objectMapper.writeValueAsString(
                CreatePaymentRequest.builder()
                    .senderAccountId("GB29NWBK60161331926819")
                    .receiverAccountId("GB82WEST12345698765432")
                    .receiverBankCode("BARCGB22")
                    .amount(new BigDecimal("-10.00"))  // ← Invalid
                    .currency(Currency.GBP)
                    .paymentType(PaymentType.DOMESTIC)
                    .build()
            );

            mockMvc.perform(post("/api/v1/payments")
                    .contentType(MediaType.APPLICATION_JSON)
                    .content(badRequest))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"))
                .andExpect(jsonPath("$.fieldErrors.amount").exists());

            verifyNoInteractions(paymentService);
        }

        @Test
        @DisplayName("should return 400 when required fields are missing")
        @WithMockUser(roles = "PAYMENT_INITIATOR")
        void shouldReturn400WhenMissingFields() throws Exception {
            mockMvc.perform(post("/api/v1/payments")
                    .contentType(MediaType.APPLICATION_JSON)
                    .content("{}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"))
                .andExpect(jsonPath("$.fieldErrors.senderAccountId").exists())
                .andExpect(jsonPath("$.fieldErrors.receiverAccountId").exists())
                .andExpect(jsonPath("$.fieldErrors.amount").exists());
        }

        @Test
        @DisplayName("should propagate idempotency key from header")
        @WithMockUser(roles = "PAYMENT_INITIATOR")
        void shouldForwardIdempotencyKey() throws Exception {
            when(paymentService.createPayment(any())).thenReturn(buildMockResponse());
            String idempotencyKey = UUID.randomUUID().toString();

            mockMvc.perform(post("/api/v1/payments")
                    .contentType(MediaType.APPLICATION_JSON)
                    .content(buildValidRequestJson())
                    .header("Idempotency-Key", idempotencyKey))
                .andExpect(status().isCreated());

            verify(paymentService).createPayment(
                argThat(req -> idempotencyKey.equals(req.getIdempotencyKey()))
            );
        }
    }

    // ── GET /api/v1/payments/{id} ──────────────────────────────────────────

    @Nested
    @DisplayName("GET /api/v1/payments/{id}")
    class GetPaymentById {

        @Test
        @DisplayName("should return 200 when payment found")
        @WithMockUser(roles = "PAYMENT_VIEWER")
        void shouldReturn200WhenFound() throws Exception {
            when(paymentService.getPaymentById(PAYMENT_ID)).thenReturn(buildMockResponse());

            mockMvc.perform(get("/api/v1/payments/{id}", PAYMENT_ID))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(PAYMENT_ID.toString()))
                .andExpect(jsonPath("$.paymentReference").value(PAYMENT_REF));
        }

        @Test
        @DisplayName("should return 404 when payment not found")
        @WithMockUser(roles = "PAYMENT_VIEWER")
        void shouldReturn404WhenNotFound() throws Exception {
            when(paymentService.getPaymentById(any()))
                .thenThrow(new PaymentNotFoundException("Payment not found: " + PAYMENT_ID));

            mockMvc.perform(get("/api/v1/payments/{id}", PAYMENT_ID))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("PAYMENT_NOT_FOUND"));
        }
    }

    // ── PATCH /api/v1/payments/{id}/status ────────────────────────────────

    @Nested
    @DisplayName("PATCH /api/v1/payments/{id}/status")
    class UpdateStatus {

        @Test
        @DisplayName("should return 200 when status updated successfully")
        @WithMockUser(roles = "INTERNAL_SERVICE")
        void shouldReturn200OnValidStatusUpdate() throws Exception {
            PaymentResponse completed = PaymentResponse.builder()
                .id(PAYMENT_ID)
                .paymentReference(PAYMENT_REF)
                .status(PaymentStatus.COMPLETED)
                .amount(new BigDecimal("250.00"))
                .currency(Currency.GBP)
                .paymentType(PaymentType.DOMESTIC)
                .clearingReference("CLR-123")
                .retryCount(0)
                .createdAt(Instant.now())
                .updatedAt(Instant.now())
                .build();

            when(paymentService.updateStatus(eq(PAYMENT_ID), any())).thenReturn(completed);

            String body = objectMapper.writeValueAsString(
                UpdateStatusRequest.builder()
                    .newStatus(PaymentStatus.COMPLETED)
                    .clearingReference("CLR-123")
                    .build()
            );

            mockMvc.perform(patch("/api/v1/payments/{id}/status", PAYMENT_ID)
                    .contentType(MediaType.APPLICATION_JSON)
                    .content(body))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("COMPLETED"))
                .andExpect(jsonPath("$.clearingReference").value("CLR-123"));
        }
    }
}
