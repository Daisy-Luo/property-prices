# -*- coding: utf-8 -*-

import requests
from bs4 import BeautifulSoup
import time
import random
import re
import pandas as pd
import numpy as np
import ast
import urllib2
month = 'Jul-20'



def randHeader():
    '''
    随机生成 User-Agent
    :return:
    '''
    head_connection = ['Keep-Alive', 'close']
    head_accept = ['text/html, appliction/xhtml+xml, */*']
    head_accept_language = ['zh-CN,fr-FR;q=0.5', 'en-US,en;q=0.8,zh-Hans-CN;q=0.5,zh-Hans;q=0.3']
    head_user_agent = ['Opera/8.0 (Macintosh; PPC Mac OS X; U; en)',
                       'Opera/9.27 (Windows NT 5.2; U; zh-cn)',
                       'Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.1; Win64; x64; Trident/4.0)',
                       'Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.1; Trident/4.0)'
                       ]
    result = {
        'Connection': head_connection[0],
        'Accept': head_accept[0],
        'Accept-Language': head_accept_language[1],
        'User-Agent': head_user_agent[random.randrange(0, len(head_user_agent))]
    }
    return result

def getCurrentTime():
    return time.strftime('[%Y-%m-%d %H:%M:%S', time.localtime(time.time()))

def getPage(url, tries_num=5, sleep_time=0, time_out=10, max_retry=5):
    '''
    这里重写get函数，主要是为了实现网络中断后自动重连，同时为了兼容各种网站不同的反爬策略，通过sleep时间和timeout动态调整来测试合适的网络连接参数
    通过isproxy来控制是否使用代理，以支持一些在内网办公的童鞋
    :param url:
    :param tries_num: 重试次数
    :param sleep_time: 休眠时间
    :param time_out: 连接超时参数
    :param max_retry: 最大重试次数，仅仅为了递归使用
    :return:
    '''
    sleep_time_p = sleep_time
    time_out_p = time_out
    tries_num_p = tries_num
    try:
        # res = requests.Session()
        if isproxy == 1:
            res = requests.get(url, headers=header, timeout=time_out, proxies=proxy)
        else:
            res = requests.get(url, headers=header, timeout=time_out)
            return res
        res.raise_for_status()  # 如果响应状态码不是200， 就主动抛出异常
    except requests.HTTPError as e:
        if e.response.status_code == 404:
            print '404 Error: The page is not found!'
            return None
    except (requests.RequestException, requests.Timeout, requests.ConnectTimeout, requests.HTTPError) as e:
        sleep_time_p = sleep_time_p + 10
        time_out_p = time_out_p + 10
        tries_num_p = tries_num_p - 1
        # 设置重试次数，最大timeout时间和最长休眠时间
        if tries_num_p > 0:
            time.sleep(sleep_time_p)
            print getCurrentTime(), url, 'URL Connection Error, 第', max_retry - tries_num_p, u'次 Retry Connection', e
            return getPage(url, tries_num_p, sleep_time_p, time_out_p, max_retry)

class SoufangSpider():
    def getCurrentTime(self):
        return time.strftime('[%Y-%m-%d %H:%M:%S]', time.localtime(time.time()))

    def getAllCityURL(self):
        url = 'http://js.soufunimg.com/homepage/new/family/css/citys20171228.js?v=20170521'
        try:
            res = urllib2.Request(url, headers=header)
            page = urllib2.urlopen(res).read()
            p = range(0, 18)
            # print page[18:50524]
            names = []
            urls = []
            for i in ast.literal_eval(page[18:50524]):
                name = i.get('name')
                url = i.get('url')
                pattern = re.compile('//([a-z]+)')
                city = re.search(pattern, url)
                # print city.group()[2:]
                if name in ['北京', '上海', '广州', '深圳']:
                    urls.append(city.group()[2:])
                    names.append(name)
            AllCity = pd.DataFrame()
            AllCity['names'] = names
            AllCity['links'] = urls
            print AllCity
            return AllCity
        except urllib2.HTTPError:
            time.sleep(5)
            return self.getAllCityURL()

    def getNumofProperty(self, url):
        res = getPage(url)
        if res:
            res.encoding = 'gbk'
            soup = BeautifulSoup(res.content, 'html.parser')
            p = soup.find('a', id='allUrl')
            try:
                pages = p.find('span').get_text().strip('()')
                print 'page:', pages
                return int(pages)/19
            except:
                'No content in this page!'
                pages = 0
                return pages
        else:
            'Cannot find this page!'
            pages = 0
            return pages

    def getPropetyLinks(self, base_url):
        names = []
        links = []
        pages = self.getNumofProperty(base_url)
        # if pages > 10:
        #     pages = 10
        print 'Total pages: ', pages
        for i in range(1, pages+2):
            full_url = str(base_url) + str(i) + '/?ctm=1.bj.xf_search.page.5'
            print 'base url:', base_url, full_url
            res = getPage(full_url)
            if res:
                res.encoding = 'gbk'
                soup = BeautifulSoup(res.content, 'html.parser')
                details = soup.find_all('div', class_='nlc_details')
                if details:
                    for d in details:
                        # print 'details:', d
                        n = d.find('div', class_='nlcd_name')
                        name = n.find('a').get_text().strip()
                        # print 'n.find(a):', n.find('a')
                        link = n.find('a').get("href")
                        link = 'http:' + link
                        names.append(name)
                        links.append(link)
                        # print name
                        # print link
            property_list = pd.DataFrame()
            property_list['name'] = names
            property_list['link'] = links
            property_list = property_list.drop_duplicates(['name'])
        return property_list


    def getPropetyPrice(self, url):
        try:
            if url == 'http://http//dongdaihejzy010.fang.com' or url == 'http://fjxtzx.fang.com/':
                return 0
            print getCurrentTime(), url
            res = getPage(url)
            if res:
                res.encoding = 'gbk'
                soup = BeautifulSoup(res.content, 'html.parser')
                p = soup.find('div', class_='inf_left fl mr30')
                if p:
                    # print p
                    price = p.find('span').get_text().strip()
                    print 'price:', price
                    if price == u'待定':
                        price = 0
                        return price
                    else:
                        description = p.get_text()
                        print description
                        temp = description.strip()[9:19]
                        pattern = re.compile(r'\d+(.*?)')
                        try:
                            unit = temp.split(re.search(pattern, temp).group())[1]
                        except:
                            unit = 'Nothing'
                        print unit
                        print 'length:', len(unit)
                        if len(unit) != 4:
                            print 'unit is not yuan/m'
                            price = 0
                        elif unit[0] != u'元':
                            print 'unit is not yuan/m'
                            price = 0
                        elif unit[1] != u'/':
                            print 'unit is not yuan/m'
                            price = 0
                        elif unit[2:4] != u'm²':
                            print 'unit is not yuan/m'
                            price = 0
                        else:
                            price = price
                    return price
                else:
                    price = 0
                    return price
            else:
                price = 0
                return price
        except requests.ConnectTimeout, e:
            print e.message

    def getAvePrice(self, property_link):
        property_price = pd.DataFrame()
        property_price['name'] = property_link['name']
        property_price['link'] = property_link['link']
        add_prices = []
        prices = []
        for link in property_link['link']:
            print link
            price = self.getPropetyPrice(link)
            price = float(price)
            add_prices.append(price)
            print price
            if price > 0:
                print price
                prices.append(price)
                print 'Lenght of prices:',len(prices)
            print 'Number of properties: ', len(prices)
            # if len(prices) >= 50:
            #     break
        property_price[month] = add_prices
        print 'Property_price_list: ', property_price
        prices_mean, prices_std = np.mean(prices), np.std(prices)
        cut_off = prices_std * 3
        lower, upper = prices_mean - cut_off, prices_mean + cut_off
        prices_outliers_removed = [x for x in prices if x > lower and x < upper]
        outliers = [x for x in prices if x < lower or x > upper]
        print 'Ourliers are: ', outliers
        return np.mean(prices_outliers_removed), len(prices), property_price  # 还没有city名字


def main():
    writer2 = pd.ExcelWriter('property prices (tier 3).xlsx')
    global isproxy, proxy, header, sleep_time
    isproxy = 0
    proxy = {"http": "http://110.37.84.147:8080", "https": "http://110.37.84.147:8080"}  # 这里需要替换成可用的代理IP
    header = randHeader()
    sleep_time = 0.1
    soufang = SoufangSpider()
    AllCityURL = soufang.getAllCityURL()
    Prices = pd.DataFrame()
    names = []
    ave_price = []
    num_of_propertites = []
    for url in AllCityURL['links']:
        if url == 'bj':
            base_urls = 'http://newhouse.fang.com/house/s/b9'
        else:
            base_urls = 'http://newhouse.' + str(url) + '.fang.com/house/s/b9'
        print base_urls
        PropertyLinks = soufang.getPropetyLinks(base_urls)
        print 'property links', PropertyLinks
        AvePrice, num_of_property, property_price = soufang.getAvePrice(PropertyLinks)
        property_price.to_excel(writer2, url)
        if AvePrice is None or AvePrice == 0:
            continue
        if AvePrice:
            names.append(AllCityURL[AllCityURL['links'] == url].iloc[0]['names'])
            ave_price.append(AvePrice)
            num_of_propertites.append(num_of_property)
            print names, ave_price
        else:
            continue
    writer2.save()
    Prices['Name'] = names
    Prices['Average Price'] = ave_price
    Prices['Number of property'] = num_of_propertites
    writer = pd.ExcelWriter('Property Pricing Tracker (tier 1).xlsx')
    Prices.to_excel(writer, 'prices')
    writer.save()


if __name__ == '__main__':
    main()
