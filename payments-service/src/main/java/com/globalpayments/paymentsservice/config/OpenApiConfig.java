package com.globalpayments.paymentsservice.config;

import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Contact;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.info.License;
import io.swagger.v3.oas.models.security.SecurityRequirement;
import io.swagger.v3.oas.models.security.SecurityScheme;
import io.swagger.v3.oas.models.servers.Server;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.List;

/**
 * OpenAPI 3 (Swagger) Configuration.
 *
 * Accessible at /swagger-ui.html in non-production environments.
 * In production, Swagger UI is disabled via Spring profile:
 *   springdoc.swagger-ui.enabled=false
 *
 * This documentation is used by:
 *   - The gateway-service team to understand the internal API contract
 *   - QA team for exploratory testing in lower environments
 *   - New developers onboarding to the service
 */
@Configuration
public class OpenApiConfig {

    @Value("${spring.application.name}")
    private String applicationName;

    @Bean
    public OpenAPI paymentsServiceOpenAPI() {
        return new OpenAPI()
            .info(new Info()
                .title("Payments Service API")
                .description("""
                    **Core Payment Processing Service** — Global Payments API Platform.
                    
                    Handles the full payment lifecycle:
                    - Payment creation with idempotency support
                    - Status tracking and lifecycle management
                    - Automatic retry for failed payments
                    
                    **Note:** This is an internal service. All external traffic
                    must go through the `gateway-service`.
                    """)
                .version("v1.0.0")
                .contact(new Contact()
                    .name("Payments DevOps Team")
                    .email("payments-devops@globalpayments.com"))
                .license(new License()
                    .name("Internal — Not for public distribution"))
            )
            .servers(List.of(
                new Server().url("http://localhost:8080").description("Local Development"),
                new Server().url("https://payments-internal.bank.com").description("Production (internal)")
            ))
            // Require Bearer token on all endpoints in Swagger UI
            .addSecurityItem(new SecurityRequirement().addList("bearerAuth"))
            .components(new Components()
                .addSecuritySchemes("bearerAuth",
                    new SecurityScheme()
                        .type(SecurityScheme.Type.HTTP)
                        .scheme("bearer")
                        .bearerFormat("JWT")
                        .description("JWT token from the Identity Provider. Roles: PAYMENT_INITIATOR, PAYMENT_VIEWER, ADMIN, INTERNAL_SERVICE")
                )
            );
    }
}
