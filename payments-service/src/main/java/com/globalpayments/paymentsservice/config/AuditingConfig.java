package com.globalpayments.paymentsservice.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.domain.AuditorAware;
import org.springframework.data.jpa.repository.config.EnableJpaAuditing;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.Optional;

/**
 * JPA Auditing Configuration.
 *
 * Provides the AuditorAware bean that Spring Data JPA uses to populate
 * the @CreatedBy field on the Payment entity. In banking systems, every
 * record must carry the identity of who created it — this is a hard
 * audit-trail requirement (SOX, PCI-DSS).
 *
 * The value populated comes from the authenticated principal extracted
 * by the JwtAuthFilter (set on the SecurityContext per request).
 */
@Configuration
@EnableJpaAuditing(auditorAwareRef = "auditorProvider")
public class AuditingConfig {

    /**
     * Returns the currently authenticated user's identifier (subject claim
     * from the JWT) for stamping onto entity @CreatedBy fields.
     *
     * Falls back to "system" for:
     *   - Scheduled jobs (retry processor, stale-payment scanner)
     *   - Internal service calls without a user context
     */
    @Bean
    public AuditorAware<String> auditorProvider() {
        return () -> {
            Authentication auth = SecurityContextHolder.getContext().getAuthentication();

            if (auth == null || !auth.isAuthenticated()) {
                return Optional.of("system");
            }

            String principal = auth.getName();
            return Optional.ofNullable(principal).filter(p -> !p.isBlank())
                           .or(() -> Optional.of("system"));
        };
    }
}
