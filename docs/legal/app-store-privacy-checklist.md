# 知读 ReadU 上架隐私核对表

这份清单用于让 App Store Connect 的隐私标签、App 内说明和后端实际行为保持一致。它不是法律意见；正式大范围上线前应由熟悉目标市场的专业人士复核。

## 上架前必须填写

- `LEGAL_OPERATOR_NAME`：Apple Developer 账号登记的真实法定姓名或公司全称。
- `PRIVACY_EMAIL`：能长期接收隐私、注销、举报和版权请求的邮箱。
- `LEGAL_EFFECTIVE_DATE`：本次政策生效日期。
- `LEGAL_POLICY_VERSION`：政策版本号。

## App Store Connect 链接

- Privacy Policy URL：`https://api.youxugarden.com/legal/privacy`
- 英文隐私政策：`https://api.youxugarden.com/legal/privacy/en`
- 账号删除说明：`https://api.youxugarden.com/legal/account-deletion`

所有链接必须在未登录、无 Cookie、手机网络环境下正常打开。

## 当前版本的数据事实

- 用户导入的 EPUB、TXT、PDF 原始文件默认只保存在设备中，不因普通导入自动上传。
- 登录后会同步书籍元信息、阅读进度、书签、划线、想法、小U记录、随心记和小U对话。
- 小U使用 DeepSeek；API Key 只在服务器环境变量中。
- 小U可能发送选区、上下文、当前页或章节、问题、近期阅读痕迹、对话历史和主动授权的随心记。
- 明台内容默认私人，只有用户明确确认后才公开。
- 当前没有广告、广告标识符、跨 App 跟踪或第三方统计分析 SDK。
- 账号可在 App 内永久注销；轮换数据库备份最长保留 14 天。

## 隐私标签填写提示

最终答案必须以提交审核时的代码和生产配置为准。当前通常需要评估并披露：

- Contact Info：Email Address。
- User Content：Photos（头像）、Other User Content（笔记、对话、公开帖子和评论）。
- Identifiers：User ID。
- Usage Data：Product Interaction（阅读进度、互动等，如用于产品功能）。
- Diagnostics：Crash Data / Other Diagnostic Data（仅在生产环境实际采集时勾选）。

用途通常包括 App Functionality、Developer Communications、Security/Fraud Prevention。当前不得勾选 Tracking，也不要声明用于第三方广告。

## 提审前真机验收

1. 未登录打开“设置 → 隐私与安全 → 隐私政策”。
2. 首次使用小U出现 DeepSeek 即时告知，并可拒绝。
3. 拒绝后基础阅读仍可使用；撤回后小U停止调用第三方 AI。
4. 发布明台内容前明确预览公开范围，默认不公开。
5. 帖子和评论可举报，可拉黑用户，设置页可找到客服与举报渠道。
6. “设置 → 账户 → 注销账号”可直接发起永久删除，不只停用账号。
7. 删除公开帖子后，其公开摘录与关联互动按产品规则一并删除。
8. 生产包只使用 HTTPS，不包含 DeepSeek API Key、证书私钥或测试账号。

## 发布后维护

- 功能、SDK、云服务商、AI 模型供应商或数据用途变化时，先更新政策与隐私标签，再发布版本。
- DeepSeek 条款变化时复核训练、留存、处理地区和下游告知要求。
- 定期测试 HTTPS 证书续期、备份恢复、账号注销和公开内容删除。
