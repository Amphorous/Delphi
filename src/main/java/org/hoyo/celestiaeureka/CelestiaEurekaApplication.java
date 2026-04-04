package org.hoyo.celestiaeureka;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.netflix.eureka.server.EnableEurekaServer;

@EnableEurekaServer
@SpringBootApplication
public class CelestiaEurekaApplication {

    public static void main(String[] args) {
        SpringApplication.run(CelestiaEurekaApplication.class, args);
    }

}
