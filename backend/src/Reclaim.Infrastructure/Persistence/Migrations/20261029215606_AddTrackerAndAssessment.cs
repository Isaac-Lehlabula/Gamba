using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Reclaim.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddTrackerAndAssessment : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "GamblingPlatform",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    NormalizedName = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    CreatedByUserProfileId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_GamblingPlatform", x => x.Id);
                    table.ForeignKey(
                        name: "FK_GamblingPlatform_UserProfile_CreatedByUserProfileId",
                        column: x => x.CreatedByUserProfileId,
                        principalTable: "UserProfile",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "OnboardingResponse",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserProfileId = table.Column<Guid>(type: "uuid", nullable: false),
                    GamblingTypes = table.Column<string[]>(type: "text[]", nullable: false),
                    FrequencyBand = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    ApproxMonthlySpend = table.Column<decimal>(type: "numeric(12,2)", precision: 12, scale: 2, nullable: true),
                    Triggers = table.Column<string[]>(type: "text[]", nullable: false),
                    Goal = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    MoneyGoalPreference = table.Column<string>(type: "text", nullable: true),
                    CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_OnboardingResponse", x => x.Id);
                    table.ForeignKey(
                        name: "FK_OnboardingResponse_UserProfile_UserProfileId",
                        column: x => x.UserProfileId,
                        principalTable: "UserProfile",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "SelfAssessmentResult",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserProfileId = table.Column<Guid>(type: "uuid", nullable: false),
                    QuestionnaireVersion = table.Column<int>(type: "integer", nullable: false),
                    Answers = table.Column<string>(type: "jsonb", nullable: false),
                    Score = table.Column<int>(type: "integer", nullable: false),
                    RiskLevel = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_SelfAssessmentResult", x => x.Id);
                    table.ForeignKey(
                        name: "FK_SelfAssessmentResult_UserProfile_UserProfileId",
                        column: x => x.UserProfileId,
                        principalTable: "UserProfile",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "GamblingEntry",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserProfileId = table.Column<Guid>(type: "uuid", nullable: false),
                    EntryType = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    Amount = table.Column<decimal>(type: "numeric(12,2)", precision: 12, scale: 2, nullable: false),
                    OccurredAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    GamblingType = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    GamblingPlatformId = table.Column<Guid>(type: "uuid", nullable: true),
                    Notes = table.Column<string>(type: "text", nullable: true),
                    CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_GamblingEntry", x => x.Id);
                    table.ForeignKey(
                        name: "FK_GamblingEntry_GamblingPlatform_GamblingPlatformId",
                        column: x => x.GamblingPlatformId,
                        principalTable: "GamblingPlatform",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "FK_GamblingEntry_UserProfile_UserProfileId",
                        column: x => x.UserProfileId,
                        principalTable: "UserProfile",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_GamblingEntry_GamblingPlatformId",
                table: "GamblingEntry",
                column: "GamblingPlatformId");

            migrationBuilder.CreateIndex(
                name: "IX_GamblingEntry_UserProfileId_OccurredAtUtc",
                table: "GamblingEntry",
                columns: new[] { "UserProfileId", "OccurredAtUtc" });

            migrationBuilder.CreateIndex(
                name: "IX_GamblingPlatform_CreatedByUserProfileId_NormalizedName",
                table: "GamblingPlatform",
                columns: new[] { "CreatedByUserProfileId", "NormalizedName" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_OnboardingResponse_UserProfileId_CreatedAtUtc",
                table: "OnboardingResponse",
                columns: new[] { "UserProfileId", "CreatedAtUtc" });

            migrationBuilder.CreateIndex(
                name: "IX_SelfAssessmentResult_UserProfileId_CreatedAtUtc",
                table: "SelfAssessmentResult",
                columns: new[] { "UserProfileId", "CreatedAtUtc" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "GamblingEntry");

            migrationBuilder.DropTable(
                name: "OnboardingResponse");

            migrationBuilder.DropTable(
                name: "SelfAssessmentResult");

            migrationBuilder.DropTable(
                name: "GamblingPlatform");
        }
    }
}
