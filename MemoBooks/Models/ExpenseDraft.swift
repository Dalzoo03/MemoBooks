import FoundationModels

// Date is deliberately represented as a guided string in the generated schema.
// Convert and strictly validate it in app code before presenting the draft.
// https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation
@Generable
struct ExpenseDraft {
    @Guide(description: "돈을 쓴 경우 expense, 급여·용돈 등 받은 경우 income. 계좌 간 이동은 수입이 아님",
           .anyOf(["expense", "income"]))
    var kind: String

    @Guide(description: "실제 수입 또는 지출의 원 단위 정수 금액. 입력에 금액이 없거나 여러 지출로 불명확하면 nil. 추측 금지")
    var amount: Int?

    @Guide(description: "가게명 또는 거래 목적. 짧은 한국어 메모")
    var memo: String

    @Guide(description: "지출 날짜를 yyyy-MM-dd 형식으로 반환. 상대 날짜는 제공된 오늘 날짜 기준으로 변환. 날짜 언급이 없으면 오늘")
    var dateText: String

    @Guide(description: "거래 유형에 맞는 카테고리. 커피=카페, 월세=주거, 옷=쇼핑, 병원=의료, 영화=문화",
           .anyOf(ExpenseCategory.allCases.map(\.rawValue)))
    var category: String

}
