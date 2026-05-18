package com.globalpayments.paymentsservice.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.List;

/**
 * Spring Security configuration.
 *
 * Strategy:
 * - Stateless JWT authentication (no sessions — required for horizontal scaling)
 * - Role-based access via @PreAuthorize on controller methods
 * - Actuator endpoints secured to internal network only
 * - All payment endpoints require authentication
 */
@Configuration
@EnableWebSecurity
@EnableMethodSecurity(prePostEnabled = true)
@RequiredArgsConstructor
public class SecurityConfig {

    private final JwtAuthFilter jwtAuthFilter;

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            // Stateless — no CSRF needed for token-based APIs
            .csrf(csrf -> csrf.disable())

            // Stateless sessions — pods are interchangeable
            .sessionManagement(sm ->
                sm.sessionCreationPolicy(SessionCreationPolicy.STATELESS))

            .authorizeHttpRequests(auth -> auth
                // Actuator health/prometheus endpoints — accessible from cluster only
                // (network policy ensures this, not security config)
                .requestMatchers(
                    "/actuator/health",
                    "/actuator/health/**",
                    "/actuator/prometheus"
                ).permitAll()

                // OpenAPI docs — disable in prod via profile
                .requestMatchers("/swagger-ui/**", "/v3/api-docs/**").permitAll()

                // All payment endpoints require authentication
                .anyRequest().authenticated()
            )

            .addFilterBefore(jwtAuthFilter, UsernamePasswordAuthenticationFilter.class);

        return http.build();
    }
}

/**
 * JWT validation filter.
 * Runs once per request, extracts and validates the Bearer token,
 * and populates the SecurityContext.
 */
@Component
@Slf4j
class JwtAuthFilter extends OncePerRequestFilter {

    @Value("${app.jwt.secret}")
    private String jwtSecret;

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain) throws ServletException, IOException {

        String authHeader = request.getHeader("Authorization");

        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            filterChain.doFilter(request, response);
            return;
        }

        String token = authHeader.substring(7);

        try {
            JwtClaims claims = validateAndExtract(token);

            List<SimpleGrantedAuthority> authorities = claims.roles().stream()
                    .map(role -> new SimpleGrantedAuthority("ROLE_" + role))
                    .toList();

            var authentication = new UsernamePasswordAuthenticationToken(
                    new User(claims.subject(), "", authorities),
                    null,
                    authorities
            );

            SecurityContextHolder.getContext().setAuthentication(authentication);

        } catch (Exception e) {
            log.warn("JWT validation failed: {}", e.getMessage());
            // Don't set authentication — request will fail at the authorization stage
        }

        filterChain.doFilter(request, response);
    }

    private JwtClaims validateAndExtract(String token) {
        // In production: use io.jsonwebtoken.Jwts.parserBuilder()
        // to validate signature, expiry, and issuer.
        // Simplified here for clarity:
        var parser = io.jsonwebtoken.Jwts.parser()
                .verifyWith(io.jsonwebtoken.security.Keys.hmacShaKeyFor(
                        jwtSecret.getBytes()))
                .build();

        var claims = parser.parseSignedClaims(token).getPayload();

        @SuppressWarnings("unchecked")
        List<String> roles = (List<String>) claims.get("roles");

        return new JwtClaims(claims.getSubject(), roles != null ? roles : List.of());
    }

    record JwtClaims(String subject, List<String> roles) {}
}
