package com.globalpayments.paymentsservice.config;

import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.common.serialization.StringSerializer;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.core.DefaultKafkaProducerFactory;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.core.ProducerFactory;
import org.springframework.kafka.support.serializer.JsonSerializer;

import java.util.HashMap;
import java.util.Map;

/**
 * Kafka Producer Configuration.
 *
 * Provides the KafkaTemplate bean injected into PaymentService.
 * Key settings for banking-grade reliability:
 *
 *   - acks=all          : Leader + all ISR replicas must acknowledge (no data loss)
 *   - idempotence=true  : Exactly-once producer semantics (no duplicate messages)
 *   - retries=3         : Retry transient broker errors before failing
 *   - linger.ms=5       : Micro-batch for throughput vs latency trade-off
 */
@Configuration
public class KafkaConfig {

    @Value("${spring.kafka.bootstrap-servers}")
    private String bootstrapServers;

    @Bean
    public ProducerFactory<String, Object> producerFactory() {
        Map<String, Object> props = new HashMap<>();

        // Connection
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);

        // Serialization
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG,   StringSerializer.class);
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, JsonSerializer.class);

        // Reliability — mandatory in financial messaging
        props.put(ProducerConfig.ACKS_CONFIG,            "all");
        props.put(ProducerConfig.RETRIES_CONFIG,         3);
        props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, true);

        // Throughput tuning
        props.put(ProducerConfig.LINGER_MS_CONFIG,           5);
        props.put(ProducerConfig.BATCH_SIZE_CONFIG,          16384);
        props.put(ProducerConfig.COMPRESSION_TYPE_CONFIG,    "snappy");

        // Prevent producer from hanging indefinitely on broker issues
        props.put(ProducerConfig.REQUEST_TIMEOUT_MS_CONFIG,  30000);
        props.put(ProducerConfig.DELIVERY_TIMEOUT_MS_CONFIG, 120000);

        // Serializer: include type info so consumers can deserialize properly
        props.put(JsonSerializer.ADD_TYPE_INFO_HEADERS, false);

        return new DefaultKafkaProducerFactory<>(props);
    }

    @Bean
    public KafkaTemplate<String, Object> kafkaTemplate() {
        KafkaTemplate<String, Object> template = new KafkaTemplate<>(producerFactory());
        template.setObservationEnabled(true); // Enable Micrometer tracing for Kafka
        return template;
    }
}
