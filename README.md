# Mandarin Acoustic Analysis Toolkit

本项目包含用于普通话实验语音学研究的 Praat 和 R 脚本。

## 主要功能

- 使用 Praat 逐区间检查和修改 TextGrid 标注，自动缩放和播放音频
- 使用 R 分析已提取的音节、元音及非元音时长、元音比例和 F0 声学指标
- 使用线性混合效应模型比较 sentential negation（SN）与 potential complement（NPC）
- 检查发音语速差异及语速调整后的时长差异
- 导出 CSV 统计结果、模型文件和残差诊断图
- 绘制时间归一化的描述性 F0 轮廓

当前版本不包含从 WAV/TextGrid 自动提取声学参数的脚本；R 脚本读取已经提取的测量 CSV。当前代码语言为 Praat 和 R，不包含 Python 脚本。

## 文件

- `check_textgrids.praat`：在 Praat 中检查并编辑同名 WAV/TextGrid；切换文件时可保存标注，使用前请备份。
- `analyze_acoustics.R`：duration 和 F0 指标的线性混合效应分析。
- `plot_f0_contours.R`：十段时间归一化 F0 的描述性轮廓图。
- `USAGE.md`：输入列名、单位、分析设定及运行说明。

## 快速开始

在 R 中安装依赖：

```r
install.packages(c("lme4", "lmerTest"))
```

命令行运行（请替换示例路径）：

```text
Rscript analyze_acoustics.R measurements.csv results
Rscript analyze_acoustics.R path/to/S results
Rscript plot_f0_contours.R path/to/S results
```

文件夹输入模式只读取 `S##_20%.csv`，并使用已有的半音制 F0 列。通用 CSV 模式所需列名见 `USAGE.md`。不随仓库提供真实实验数据。

## 方法与验证状态

代码在 Codex 辅助下生成，并根据实际研究需求进行修改和测试。R 脚本已在一组现有声学 CSV 上试跑；部分指标需要简化随机效应结构，F0 降幅模型在当前规则下仍存在奇异拟合。部分时长残差显示异方差和尾部偏离，模型输出须结合诊断评估，不能仅凭成功运行作为最终研究结论。F0 轮廓图为描述性图，不是逐时间点显著性检验。

新编写的 R 脚本与此前用于生成输入 CSV 的处理流程应区分记录。本仓库不宣称包含完整声学提取流水线。

## 数据与隐私

本仓库不包含未经授权的参与者录音或个人信息，也不包含真实 TextGrid、参与者问卷、实验 CSV、拟合模型或真实数据分析结果。
