using System.Diagnostics;
using FluentValidation;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Reclaim.Application.Common;
using Reclaim.Domain.Common;

namespace Reclaim.Api.Infrastructure;

/// <summary>
/// Maps known exceptions to RFC 7807 responses. Anything unexpected becomes a generic 500 that
/// carries only a correlation id; the detail stays in the server log.
/// </summary>
internal sealed class ApiExceptionHandler(IProblemDetailsService problemDetails, ILogger<ApiExceptionHandler> logger) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext httpContext, Exception exception, CancellationToken cancellationToken)
    {
        var correlationId = Activity.Current?.Id ?? httpContext.TraceIdentifier;

        ProblemDetails problem = exception switch
        {
            ValidationException ve => new ValidationProblemDetails(
                ve.Errors.GroupBy(e => e.PropertyName).ToDictionary(g => g.Key, g => g.Select(e => e.ErrorMessage).ToArray()))
            {
                Status = StatusCodes.Status400BadRequest,
                Title = "One or more validation errors occurred.",
            },
            DomainException de => new ProblemDetails { Status = StatusCodes.Status400BadRequest, Title = "Request could not be applied.", Detail = de.Message },
            AuthenticationFailedException ae => new ProblemDetails { Status = StatusCodes.Status401Unauthorized, Title = ae.Message },
            NotFoundException ne => new ProblemDetails { Status = StatusCodes.Status404NotFound, Title = "Not found.", Detail = ne.Message },
            ConflictException ce => new ProblemDetails { Status = StatusCodes.Status409Conflict, Title = "Conflict.", Detail = ce.Message },
            _ => new ProblemDetails { Status = StatusCodes.Status500InternalServerError, Title = "Something went wrong on our side." },
        };

        if (problem.Status == StatusCodes.Status500InternalServerError)
            logger.LogError(exception, "Unhandled exception, correlation id {CorrelationId}", correlationId);

        problem.Extensions["correlationId"] = correlationId;
        httpContext.Response.StatusCode = problem.Status!.Value;
        return await problemDetails.TryWriteAsync(new ProblemDetailsContext
        {
            HttpContext = httpContext,
            ProblemDetails = problem,
            Exception = exception,
        });
    }
}
