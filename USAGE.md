# R 声学分析脚本使用说明

## 适用范围
这是针对 SN（sentential negation）与 NPC（potential complement）设计的声学分析脚本。Praat 检查脚本不输出声学测量 CSV，需要先完成声学提取。R 脚本已在现有测量表上试跑；模型诊断和声学测量质量仍须独立评估。

## 安装与运行
在 R 中安装依赖（一次即可）：

```r
install.packages(c("lme4", "lmerTest"))
```

终端运行：

```text
Rscript analyze_acoustics.R measurements.csv results
```

## 输入 CSV
一行代表一个 token。必需列：

- token_id：全表唯一的 token 编号。
- speaker：说话人编号。
- item_pair：句项对编号；同一对在不同 block 中必须共用编号。
- construction：只能填 SN 或 NPC。

声学列可只提供其中一部分；缺失测量填 NA，不要填 0：

| 列名 | 含义与单位 |
| --- | --- |
| syllable_duration_ms | 音节时长，毫秒 |
| vowel_duration_ms | 元音时长，毫秒 |
| nonvocalic_duration_ms | 非元音部分时长，毫秒 |
| vowel_proportion | 元音时长/音节时长，0–1 |
| f0_onset_st | 起点 F0，半音 |
| f0_mean_st | 平均 F0，半音 |
| f0_offset_st | 终点 F0，半音 |
| f0_fall_st | F0 降幅，半音；建议定义为 onset−offset，正值代表下降 |
| f0_range_st | F0 极差，半音；最大值−最小值 |
| articulation_rate | 可选；发音语速，音节/秒，不含停顿 |

block 等额外列可保留，但目前模型不将 block 作为预测变量。脚本不会硬编码 432 tokens 或 9 位说话人，会报告实际分析样本量。

F0 输入必须已转换为半音，并明确、统一记录参考频率及测量窗口。逐帧 Hz 可按 12*log2(Hz/reference_Hz) 转换；平均 F0 是“先转半音再求平均”还是“先对 Hz 求平均再转换”需提前统一。本脚本不自动转换 F0 或自动提取轮廓。

## 分析方法
- 每项测量单独删除该项缺失值，不因另一项缺失而删掉整条 token。
- 用 REML 拟合线性混合效应模型，固定效应为 construction；SN 为参照，系数表示 NPC−SN。
- 初始随机结构：说话人及句项对的随机截距和 construction 随机斜率。
- 遇到奇异拟合或不收敛，先去掉随机效应相关；之后按估计方差从小到大移除斜率，保留截距。若仍不可接受，该项标记为失败，不输出无效模型作为成功结果。实际简化过程写入拟合日志。
- lmerTest 提供 Satterthwaite 自由度和 p 值；95% CI 使用 profile 方法，失败时输出 NA，不暗中换用另一种区间方法。
- vowel_duration_ms、f0_onset_st、f0_mean_st 标记为 primary；请仅在它们确实属于你预先确定的主要指标时保留此设置。其他分析为 exploratory。p 值不作多重比较校正。
- 若提供 articulation_rate，另外拟合语速模型，以及加入中心化语速协变量的音节时长模型。
- 不包含排除作者数据的稳健性检验。

这里用 onset、mean、offset、fall、range 描述 F0 contour；不是逐时间点的完整轮廓建模，也没有添加 GAMM。

## 输出
- construction_effects.csv：效应估计、标准误、自由度、未校正 p 值、95% CI、实际样本量与最终公式。
- 各指标的 model.rds、summary.txt、fit_log.csv 和 diagnostics.pdf。
- sessionInfo.txt：实际运行环境和软件包版本。
- failed_analyses.txt：如有失败，记录原因。

在解释结果前应检查输入单位、拟合日志、残差图与置信区间。不要将新生成的脚本描述为已经用于论文或已经验证。

官方方法参考：
https://lme4.github.io/lme4/reference/lmer.html
https://lme4.github.io/lme4/reference/isSingular.html
https://lme4.github.io/lme4/reference/confint.merMod.html


## 文件夹模式与 F0 轮廓

文件夹模式递归读取 S##_20%.csv。condition 映射到 construction；SN01 和 NPC01 映射到同一句项对01并跨block共用。closure_release_duration_ms、vowel_ratio、F0_onset_ST、F0_mean_ST、F0_offset_ST、F0_fall_ST、F0_range_ST、non_bu_articulation_rate_syll_s 分别映射到上述对应列。已有 rate_normalized_syllable_duration_ms 时也单独建模。输入中的标准化和半音参考定义必须自行记录与核实。

F0轮廓绘图脚本读取 F0_t05_ST、F0_t15_ST……F0_t95_ST。这些值应代表元音十个等时段内有效有声帧的平均值，绘图位置为各段中心，而不是瞬时采样。每段先计算说话人条件内均值，再对说话人等权平均，误差条为说话人间±1 SE。缺失段不作个体插值；输出CSV记录有效样本数。连线仅辅助观察聚合趋势，不代表完整连续轮廓模型或逐点显著性检验。

quality_flag 不作为整条token的自动排除依据，当前按各指标已有缺失值分别处理。正式分析前需核验标注和F0质量。
