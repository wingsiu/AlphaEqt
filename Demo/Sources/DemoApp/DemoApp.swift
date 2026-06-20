import AlphaEqt
import SwiftUI

struct DemoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("AlphaEqt Math Demo").font(.largeTitle)

                Group {
                    Text("Superscript:").font(.headline)
                    MathText("E = mc^2", fontSize: 32)
                    MathText("a^2 + b^2 = c^2", fontSize: 28)
                }

                Group {
                    Text("Subscript:").font(.headline)
                    MathText("x_1 + x_2 + x_n", fontSize: 28)
                    MathText("a_{ij}", fontSize: 28)
                }

                Group {
                    Text("Combined:").font(.headline)
                    MathText("x_i^2", fontSize: 28)
                }

                Group {
                    Text("Polynomial:").font(.headline)
                    MathText("x^3 - 2x^2 + 5x - 7 = 0", fontSize: 26)
                }

                Group {
                    Text("Matrix:").font(.headline)
                    MathText("\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}", fontSize: 28)
                    MathText("\\begin{bmatrix} 1 & 2 \\\\ 3 & 4 \\end{bmatrix}", fontSize: 28)
                    MathText("\\begin{pmatrix} 10 & x^2 & -3 \\\\ 4 & y_n & 5 \\\\ a_{ij} & 0 & 1 \\end{pmatrix}", fontSize: 26)
                }

                Spacer()
            }
            .padding(40)
        }
        .frame(minWidth: 500, minHeight: 600)
    }
}

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            DemoView()
        }
    }
}
