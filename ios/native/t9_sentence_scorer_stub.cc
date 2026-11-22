// iOS 版 T9 整句重排桩：替换 librime-t9/src/t9_sentence_scorer.cc（该文件硬依赖
// onnxruntime_cxx_api.h）。Android 发布包本就不打包 t9_sentence.onnx（九键长句重排
// 默认停用），所以这里返回“模型不可用”，与 Android 无模型时的行为一致；
// 其余 T9 能力（联合解码、纠错、octagram、predict）全部保留。

#include "t9_sentence_scorer.h"

namespace rime {
namespace {
bool g_grammar_loaded = false;
}

bool T9RequestSentenceScores(const std::string& model,
                             const std::vector<std::string>& texts,
                             std::vector<double>* scores) {
  // 无 ONNX 模型：始终不可用。
  (void)model;
  (void)texts;
  (void)scores;
  return false;
}

int T9SentenceRefinementState() { return 0; }

void T9CancelSentenceScores() {}

bool T9RefiningSentences() { return false; }

void T9SetRefiningSentences(bool active) { (void)active; }

void T9ReleaseSentenceScorer() { g_grammar_loaded = false; }

void T9SetGrammarStatus(bool loaded) { g_grammar_loaded = loaded; }

std::string T9ScoringStatus() {
  return std::string("grammar=") + (g_grammar_loaded ? "ready" : "unavailable") +
         ";sentence=disabled_ios";
}

bool T9SentenceScorerReady() { return false; }

}  // namespace rime
