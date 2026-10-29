import json

from app.schemas.story_parser import StoryParseRequest
from app.services.story_parser_service import StoryParserService


def main() -> None:
    request = StoryParseRequest(
        text=(
            "今天工作很累，不过和朋友吃晚饭还是挺开心。"
            "晚饭一共花了80块，里面那杯饮料居然33块，"
            "太贵了。后来妈妈帮我买了六盎司咖啡豆，"
            "价格18块，不用我付。"
            "朋友还请我喝了一杯8块的奶茶。"
        ),
        default_currency="CAD",
    )

    service = StoryParserService()
    result = service.parse(request)

    print(
        json.dumps(
            result.model_dump(mode="json"),
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()