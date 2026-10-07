import Defaults
import SwiftUI

struct FleetNowView: View {
    let jobs: [FleetJob]

    @Default(.fleetSkin) private var fleetSkin
    private var theme: FleetTheme { FleetTheme(skin: fleetSkin) }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if jobs.isEmpty {
                Text("Nothing running")
                    .font(.system(size: 11))
                    .foregroundColor(theme.dim)
                    .frame(height: 14)
            } else {
                ForEach(Array(jobs.prefix(2))) { job in
                    jobRow(job)
                }
                if jobs.count > 2 {
                    Text("+\(jobs.count - 2) more")
                        .font(.system(size: 11))
                        .foregroundColor(theme.dim)
                        .frame(height: 14)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 9)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.line)
                .frame(height: 1)
        }
        .frame(height: 70, alignment: .topLeading)
    }

    // MARK: - Job Row

    @ViewBuilder
    private func jobRow(_ job: FleetJob) -> some View {
        HStack(spacing: 10) {
            Text(job.pill)
                .font(.system(size: 10))
                .foregroundColor(theme.accent)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 1)
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(theme.pillBorder, lineWidth: 1)
                }
                .frame(width: 76, alignment: .leading)

            Text(job.label)
                .font(.system(size: 12))
                .foregroundColor(theme.jobText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(FleetFormat.elapsed(job.elapsedSec))
                .font(.system(size: 12))
                .foregroundColor(theme.dim)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 52, alignment: .trailing)
        }
        .frame(height: 18)
    }
}
