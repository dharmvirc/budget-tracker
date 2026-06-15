package com.budgettracker.common;

import com.fasterxml.jackson.annotation.JsonInclude;
import lombok.Builder;
import lombok.Getter;

import java.util.List;

@Getter
@Builder
@JsonInclude(JsonInclude.Include.NON_NULL)
public class ApiResponse<T> {
    private final int status;
    private final String message;
    private final T data;
    private final List<FieldError> errors;

    @Getter
    @Builder
    public static class FieldError {
        private final String field;
        private final String message;
    }

    public static <T> ApiResponse<T> ok(T data) {
        return ApiResponse.<T>builder().status(200).data(data).build();
    }

    public static <T> ApiResponse<T> created(T data) {
        return ApiResponse.<T>builder().status(201).data(data).build();
    }

    public static ApiResponse<Void> message(int status, String message) {
        return ApiResponse.<Void>builder().status(status).message(message).build();
    }
}
