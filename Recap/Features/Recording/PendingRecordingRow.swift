import SwiftUI

/// A recording that has been stopped but hasn't landed in the library yet.
///
/// It carries its placeholder date title, because the real one is generated from
/// the transcript after the save. Shown for the same reason the import rows are:
/// work the user just started should be visible where its result will be, not
/// only once the round trip finishes.
struct PendingRecordingRow: View {
    let upload: RecordingManager.PendingUpload

    var body: some View {
        AppCard {
            HStack {
                AppChip(text: upload.isWaiting ? "Waiting" : "Saving")
                Spacer()
                Text(upload.createdAt, format: .dateTime.day().month(.abbreviated).year())
                    .appTextStyle(.mono)
                    .foregroundStyle(AppColors.textTertiary)
            }
            Text(upload.title)
                .appTextStyle(.bodyMedium)
                .foregroundStyle(AppColors.textPrimary)

            Text(upload.isWaiting
                 ? "Kept on this phone. It’s added to your library next time recap opens."
                 : "Saving to your library…")
                .appTextStyle(.small)
                .foregroundStyle(AppColors.textTertiary)
        }
    }
}
